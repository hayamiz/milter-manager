/* -*- Mode: C; indent-tabs-mode: nil; c-basic-offset: 4 -*- */
/*
 *  Copyright (C) 2008-2009  Kouhei Sutou <kou@cozmixng.org>
 *
 *  This library is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU Lesser General Public License as published by
 *  the Free Software Foundation, either version 3 of the License, or
 *  (at your option) any later version.
 *
 *  This library is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU Lesser General Public License for more details.
 *
 *  You should have received a copy of the GNU Lesser General Public License
 *  along with this library.  If not, see <http://www.gnu.org/licenses/>.
 *
 */

#include <string.h>

#include <glib/gstdio.h>

#include <milter/manager/milter-manager-controller-context.h>
#include <milter/manager/milter-manager-control-command-encoder.h>
#include <milter/manager/milter-manager-control-reply-encoder.h>
#include <milter/manager/milter-manager-enum-types.h>

#include <milter-test-utils.h>
#include <milter-manager-test-utils.h>
#include <milter-manager-test-client.h>
#include <milter-manager-test-scenario.h>

#include <gcutter.h>

void test_set_configuration (void);
void test_set_configuration_failed (void);
void test_reload (void);

static MilterManager *manager;
static MilterManagerControllerContext *context;

static GError *expected_error;
static GError *actual_error;

static MilterWriter *writer;
static GIOChannel *output_channel;

static MilterManagerControlCommandEncoder *command_encoder;
static MilterManagerControlReplyEncoder *reply_encoder;

static gchar *packet;
static gsize packet_size;

static gchar *tmp_dir;
static gchar *custom_config_path;

static void
setup_input_io (void)
{
    GIOChannel *channel;
    MilterReader *input_reader;

    channel = gcut_string_io_channel_new(NULL);
    g_io_channel_set_encoding(channel, NULL, NULL);
    gcut_string_io_channel_set_pipe_mode(channel, TRUE);

    input_reader = milter_reader_io_channel_new(channel);
    milter_agent_set_reader(MILTER_AGENT(context), input_reader);
    g_object_unref(input_reader);

    writer = milter_writer_io_channel_new(channel);
    milter_writer_start(writer, NULL);

    g_io_channel_unref(channel);
}

static void
setup_output_io (void)
{
    MilterWriter *output_writer;

    output_channel = gcut_string_io_channel_new(NULL);
    g_io_channel_set_encoding(output_channel, NULL, NULL);
    gcut_string_io_channel_set_pipe_mode(output_channel, TRUE);

    output_writer = milter_writer_io_channel_new(output_channel);
    milter_agent_set_writer(MILTER_AGENT(context), output_writer);
    g_object_unref(output_writer);
}

static void
setup_io (void)
{
    setup_input_io();
    setup_output_io();
    milter_agent_start(MILTER_AGENT(context), NULL);
}

void
setup (void)
{
    MilterManagerConfiguration *config;
    MilterEncoder *encoder;

    config = milter_manager_configuration_new(NULL);
    manager = milter_manager_new(config);
    g_object_unref(config);
    context = milter_manager_controller_context_new(manager);

    setup_io();

    encoder = milter_manager_control_command_encoder_new();
    command_encoder = MILTER_MANAGER_CONTROL_COMMAND_ENCODER(encoder);
    encoder = milter_manager_control_reply_encoder_new();
    reply_encoder = MILTER_MANAGER_CONTROL_REPLY_ENCODER(encoder);

    expected_error = NULL;
    actual_error = NULL;

    packet = NULL;
    packet_size = 0;

    tmp_dir = g_build_filename(milter_test_get_base_dir(),
                               "tmp",
                               NULL);
    if (g_mkdir_with_parents(tmp_dir, 0700) == -1)
        cut_assert_errno();
    milter_manager_configuration_prepend_load_path(config, tmp_dir);

    custom_config_path = g_build_filename(tmp_dir,
                                          CUSTOM_CONFIG_FILE_NAME,
                                          NULL);
}

void
teardown (void)
{
    if (manager)
        g_object_unref(manager);
    if (context)
        g_object_unref(context);

    if (writer)
        g_object_unref(writer);
    if (output_channel)
        g_io_channel_unref(output_channel);

    if (command_encoder)
        g_object_unref(command_encoder);
    if (reply_encoder)
        g_object_unref(reply_encoder);

    if (actual_error)
        g_error_free(actual_error);
    if (expected_error)
        g_error_free(expected_error);

    if (packet)
        g_free(packet);

    if (tmp_dir) {
        g_chmod(tmp_dir, 0700);
        cut_remove_path(tmp_dir, NULL);
        g_free(tmp_dir);
    }

    if (custom_config_path)
        g_free(custom_config_path);
}

void
test_set_configuration (void)
{
    const gchar configuration[] = "XXX";
    GString *output;
    GError *error = NULL;

    cut_assert_path_not_exist(custom_config_path);

    milter_manager_control_command_encoder_encode_set_configuration(
        command_encoder,
        &packet, &packet_size,
        configuration, strlen(configuration));
    milter_writer_write(writer, packet, packet_size, NULL, &error);
    gcut_assert_error(error);
    milter_test_pump_all_events();

    cut_assert_path_exist(custom_config_path);

    g_free(packet);
    milter_manager_control_reply_encoder_encode_success(reply_encoder,
                                                        &packet, &packet_size);
    output = gcut_string_io_channel_get_string(output_channel);
    cut_assert_equal_memory(packet, packet_size,
                            output->str, output->len);
}

void
test_set_configuration_failed (void)
{
    MilterManagerConfiguration *config;
    const gchar configuration[] = "XXX";
    GString *output;
    guint packet_size_space;
    GError *error = NULL;

    config = milter_manager_get_configuration(manager);
    milter_manager_configuration_clear_load_paths(config);
    milter_manager_configuration_prepend_load_path(config, tmp_dir);

    cut_assert_path_not_exist(custom_config_path);

    g_chmod(tmp_dir, 0000);
    milter_manager_control_command_encoder_encode_set_configuration(
        command_encoder,
        &packet, &packet_size,
        configuration, strlen(configuration));
    milter_writer_write(writer, packet, packet_size, NULL, &error);
    gcut_assert_error(error);
    milter_test_pump_all_events();

    cut_assert_path_not_exist(custom_config_path);

    g_free(packet);
    milter_manager_control_reply_encoder_encode_error(
        reply_encoder,
        &packet, &packet_size,
        "");
    output = gcut_string_io_channel_get_string(output_channel);

    packet_size_space = sizeof(guint32);
    cut_assert_equal_memory(packet + packet_size_space,
                            packet_size - packet_size_space,
                            output->str + packet_size_space,
                            packet_size - packet_size_space);
    cut_assert_match(cut_take_printf(
                         "failed to save custom configuration file: "
                         "can't find writable custom configuration file in "
                         "\\[\"%s\"\\(.+\\)\\]",
                         custom_config_path),
                     output->str + packet_size);

}

void
test_reload (void)
{
    MilterManagerConfiguration *config;
    GString *output;
    GError *error = NULL;

    config = milter_manager_get_configuration(manager);
    cut_assert_false(milter_manager_configuration_is_privilege_mode(config));
    g_file_set_contents(custom_config_path,
                        "<?xml version='1.0' encoding='utf-8'?>\n"
                        "<configuration>\n"
                        "  <security>\n"
                        "    <privilege-mode>true</privilege-mode>\n"
                        "  </security>\n"
                        "</configuration>",
                        -1,
                        &error);
    gcut_assert_error(error);

    milter_manager_control_command_encoder_encode_reload(command_encoder,
                                                         &packet, &packet_size);
    milter_writer_write(writer, packet, packet_size, NULL, &error);
    gcut_assert_error(error);
    milter_test_pump_all_events();
    cut_assert_true(milter_manager_configuration_is_privilege_mode(config));

    g_free(packet);
    milter_manager_control_reply_encoder_encode_success(reply_encoder,
                                                        &packet, &packet_size);
    output = gcut_string_io_channel_get_string(output_channel);
    cut_assert_equal_memory(packet, packet_size,
                            output->str, output->len);
}

/*
vi:ts=4:nowrap:ai:expandtab:sw=4
*/
