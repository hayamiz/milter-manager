require 'pathname'
require 'shellwords'
require 'erb'
require 'yaml'
require "English"

require "rexml/document"
require "rexml/streamlistener"

require 'milter'
require 'milter_manager.so'

module Milter::Manager
  class ConfigurationLoader
    class Error < StandardError
    end

    class InvalidValue < Error
      def initialize(target, available_values, actual_value)
        @target = target
        @available_values = available_values
        @actual_value = actual_value
        super("#{@target} should be one of #{@available_values.inspect} " +
              "but was #{@actual_value.inspect}")
      end
    end

    class << self
      def load(configuration, file)
        new(configuration).load_configuration(file)
      end

      def load_custom(configuration, file)
        new(configuration).load_custom_configuration(file)
      end
    end

    attr_reader :security, :control, :manager
    attr_reader :configuration, :applicable_conditions
    def initialize(configuration)
      @configuration = configuration
      @security = SecurityConfiguration.new(configuration)
      @control = ControlConfiguration.new(configuration)
      @manager = ManagerConfiguration.new(configuration)
      @applicable_conditions = {}

      @configuration.signal_connect("to-xml") do |_, xml, indent|
        unless @applicable_conditions.empty?
          xml << " " * indent + "<applicable-conditions>\n"
          @applicable_conditions.each do |name, condition|
            xml << condition.to_xml(indent + 2)
          end
          xml << " " * indent + "</applicable-conditions>\n"
        end
      end
    end

    def load_configuration(file)
      begin
        instance_eval(File.read(file), file)
      rescue Exception => error
        location = error.backtrace[0].split(/(:\d+):?/, 2)[0, 2].join
        puts "#{location}: #{error.message}(#{error.class})"
        # FIXME: log full error
      end
    end

    def load_custom_configuration(file)
      first_line = File.open(file) {|config| config.gets}
      case first_line
      when /\A\s*</m
        XMLConfigurationLoader.new(self).load(file)
#       when /\A#\s*-\*-\s*yaml\s*-\*-/i
#         YAMLConfigurationLoader.new(self).load(file)
      else
        load_configuration(file)
      end
    end

    def define_milter(name, &block)
      egg_configuration = EggConfiguration.new(name, self)
      yield(egg_configuration)
      egg_configuration.apply
    end

    def define_applicable_condition(name)
      condition = ApplicableCondition.new(name)
      yield(condition)
      @applicable_conditions[name] = condition
    end

    class XMLConfigurationLoader
      def initialize(configuration)
        @configuration = configuration
      end

      def load(file)
        listener = Listener.new(@configuration)
        File.open(file) do |input|
          REXML::Document.parse_stream(input, listener)
        end
      end

      class Listener
        include REXML::StreamListener

        def initialize(configuration)
          @configuration = configuration
          @ns_stack = [{"xml" => :xml}]
          @tag_stack = [["", :root]]
          @text_stack = ['']
          @state_stack = [:root]
          @egg = nil
        end

        def tag_start(name, attributes)
          @text_stack.push('')

          ns = @ns_stack.last.dup
          attrs = {}
          attributes.each do |n, v|
            if /\Axmlns(?:\z|:)/ =~ n
              ns[$POSTMATCH] = v
            else
              attrs[n] = v
            end
          end
          @ns_stack.push(ns)

          prefix, local = split_name(name)
          uri = _ns(ns, prefix)
          @tag_stack.push([uri, local])

          @state_stack.push(next_state(@state_stack.last, uri, local))
        end

        def tag_end(name)
          state = @state_stack.pop
          text = @text_stack.pop
          uri, local = @tag_stack.pop
          no_action_states = [:root, :configuration, :security,
                              :control, :manager, :milters]
          case state
          when *no_action_states
            # do nothing
          when :milter
            @configuration.define_milter(@egg_config["name"]) do |milter|
              milter.connection_spec = @egg_config["connection_spec"]
              milter.target_hosts.concat(@egg_config["target_host"] || [])
              milter.target_addresses.concat(@egg_config["target_address"] || [])
              milter.target_senders.concat(@egg_config["target_sender"] || [])
              milter.target_recipients.concat(@egg_config["target_recipient"] || [])
              (@egg_config["target_header"] || []).each do |name, value|
                milter.add_target_header(name, value)
              end
            end
            @egg_config = nil
          when "milter_target_header_name"
            @egg_target_header_name = text
          when "milter_target_header_value"
            @egg_target_header_value = text
          when :milter_target_header
            if @egg_target_header_name.nil?
              raise "#{current_path}/name is missing"
            end
            if @egg_target_header_value.nil?
              raise "#{current_path}/value is missing"
            end
            @egg_config["target_header"] ||= {}
            @egg_config["target_header"][@egg_target_header_name] = @egg_target_header_value
            @egg_target_header_name = nil
            @egg_target_header_value = nil
          when /\Amilter_target_/
            key = "target_#{$POSTMATCH}"
            @egg_config[key] ||= []
            @egg_config[key] << text
          when /\Amilter_/
            @egg_config[$POSTMATCH] = text
          else
            local = normalize_local(local)
            @configuration.send(@state_stack.last).send("#{local}=", text)
          end
          @ns_stack.pop
        end

        def text(data)
          @text_stack.last << data
        end

        private
        def _ns(ns, prefix)
          ns.fetch(prefix, "")
        end

        NAME_SPLIT = /^(?:([\w:][-\w\d.]*):)?([\w:][-\w\d.]*)/
        def split_name(name)
          name =~ NAME_SPLIT
          [$1 || '', $2]
        end

        def next_state(current_state, uri, local)
          local = normalize_local(local)
          case current_state
          when :root
            if local != "configuration"
              raise "root element must be <configuration>"
            end
            :configuration
          when :configuration
            case local
            when "security"
              :security
            when "control"
              :control
            when "manager"
              :manager
            when "milters"
              :milters
            else
              raise "unexpected element: #{current_path}"
            end
          when :security, :control, :manager
            if @configuration.send(current_state).respond_to?("#{local}=")
              local
            else
              raise "unexpected element: #{current_path}"
            end
          when :milter
            available_locals = ["name", "connection_spec",
                                "target_host", "target_address",
                                "target_sender", "target_recipient"]
            case local
            when "target_header"
              @egg_target_header_name = nil
              @egg_target_header_value = nil
              :milter_target_header
            when *available_locals
              "milter_#{local}"
            else
              raise "unexpected element: #{current_path}"
            end
          when :milter_target_header
            if ["name", "value"].include?(local)
              "milter_target_header_#{name}"
            else
              raise "unexpected element: #{current_path}"
            end
          when :milters
            if local == "milter"
              @egg_config = {}
              :milter
            else
              raise "unexpected element: #{current_path}"
            end
          else
            raise "unexpected element: #{current_path}"
          end
        end

        def current_path
          locals = @tag_stack.collect do |uri, local|
            local
          end
          ["", *locals].join("/")
        end

        def normalize_local(local)
          local.gsub(/-/, "_")
        end
      end
    end

    class SecurityConfiguration
      def initialize(configuration)
        @configuration = configuration
      end

      def privilege_mode?
        @configuration.privilege_mode?
      end

      def privilege_mode=(mode)
        mode = false if mode == "false"
        mode = true if mode == "true"
        available_values = [true, false]
        unless available_values.include?(mode)
          raise InvalidValue.new("security.privilege_mode",
                                 available_values,
                                 mode)
        end
        @configuration.privilege_mode = mode
      end
    end

    class ControlConfiguration
      def initialize(configuration)
        @configuration = configuration
      end

      def connection_spec=(spec)
        Milter::Connection.parse_spec(spec)
        @configuration.control_connection_spec = spec
      end
    end

    class ManagerConfiguration
      def initialize(configuration)
        @configuration = configuration
      end

      def connection_spec=(spec)
        Milter::Connection.parse_spec(spec)
        @configuration.manager_connection_spec = spec
      end
    end

    class EggConfiguration
      def initialize(name, loader)
        @egg = Egg.new(name)
        @loader = loader
        @applicable_conditions = []
      end

      def add_applicable_condition(name)
        condition = @loader.applicable_conditions[name]
        if condition.nil?
          raise InvalidValue, "applicable condition '#{name}' isn't defined"
        end
        @applicable_conditions << condition
      end

      def command_options=(options)
        if options.is_a?(Array)
          options = options.collect do |option|
            Shellwords.escape(option)
          end.join(' ')
        end
        @egg.command_options = options
      end

      def method_missing(name, *args, &block)
        @egg.send(name, *args, &block)
      end

      def apply
        setup_check_callback
        setup_to_xml_callback
        @loader.configuration.add_egg(@egg)
      end

      private
      def setup_check_callback
        if @applicable_conditions.all? {|condition| !condition.have_checker?}
          return
        end

        @egg.signal_connect("hatched") do |_, child|
          @applicable_conditions.each do |condition|
            if condition.have_checker?
              condition.apply(child)
            end
          end
        end
      end

      def setup_to_xml_callback
        return if @applicable_conditions.empty?

        @egg.signal_connect("to-xml") do |_, xml, indent|
          @applicable_conditions.each do |condition|
            xml << " " * indent + "<applicable-conditions>\n"
            condition_tag = "<applicable-condition>"
            condition_tag << ERB::Util.h(condition.name)
            condition_tag << "</applicable-condition>\n"
            xml << " " * (indent + 2) + condition_tag
            xml << " " * indent + "</applicable-conditions>\n"
          end
        end
      end
    end

    class ApplicableCondition
      attr_accessor :name, :description
      def initialize(name)
        @name = name
        @description = nil
        @connect_checkers = []
        @envelope_from_checkers = []
        @envelope_recipient_checkers = []
        @header_checkers = []
      end

      def define_connect_checker(&block)
        @connect_checkers << block
      end

      def define_envelope_from_checker(&block)
        @envelope_from_checkers << block
      end

      def define_envelope_recipient_checker(&block)
        @envelope_recipient_checkers << block
      end

      def define_header_checker(&block)
        @header_checkers << block
      end

      def have_checker?
        [@connect_checkers,
         @envelope_from_checkers,
         @envelope_recipient_checkers,
         @header_checkers].any? do |checkers|
          not checkers.empty?
        end
      end

      def apply(child)
        unless @connect_checkers.empty?
          child.signal_connect("check-connect") do |_child, host, address|
            @connect_checkers.all? do |checker|
              checker.call(_child, host, address)
            end
          end
        end

        unless @envelope_from_checkers.empty?
          child.signal_connect("check-envelope-from") do |_child, from|
            @envelope_from_checkers.all? do |checker|
              checker.call(_child, from)
            end
          end
        end

        unless @envelope_recipient_checkers.empty?
          child.signal_connect("check-envelope-recipient") do |_child, recipient|
            @envelope_recipient_checkers.all? do |checker|
              checker.call(_child, recipient)
            end
          end
        end

        unless @header_checkers.empty?
          child.signal_connect("check-header") do |_child, name, value|
            @header_checkers.all? do |checker|
              checker.call(_child, name, value)
            end
          end
        end
      end

      def to_xml(indent=nil)
        indent ||= 0
        xml = ""
        xml << " " * indent + "<applicable-condition>\n"
        xml << " " * (indent + 2) + "<name>#{ERB::Util.h(@name)}</name>\n"
        xml << " " * (indent + 2) +
          "<description>#{ERB::Util.h(@description)}</description>\n"
        xml << " " * indent + "</applicable-condition>\n"
        xml
      end
    end
  end
end
