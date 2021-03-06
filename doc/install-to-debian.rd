# -*- rd -*-

= Install to Debian --- How to install milter manager to Debian GNU/Linux

== About this document

This document describes how to install milter manager to
Debian GNU/Linux. See ((<Install|install.rd>)) for general
install information.

== Install packages

Packages for jessie, the current stable release, for stretch,
the current testing release, and for sid, the eternal
unstable, are distributed on the milter manager site.

We put the following content to
/etc/apt/sources.list.d/milter-manager.list:

=== For jessie

/etc/apt/sources.list.d/milter-manager.list:
  deb http://downloads.sourceforge.net/project/milter-manager/debian/stable jessie main
  deb-src http://downloads.sourceforge.net/project/milter-manager/debian/stable jessie main

=== For stretch

/etc/apt/sources.list.d/milter-manager.list:
  deb http://downloads.sourceforge.net/project/milter-manager/debian/stable stretch main
  deb-src http://downloads.sourceforge.net/project/milter-manager/debian/stable stretch main

=== For sid

/etc/apt/sources.list.d/milter-manager.list:
  deb http://downloads.sourceforge.net/project/milter-manager/debian/stable unstable main
  deb-src http://downloads.sourceforge.net/project/milter-manager/debian/stable unstable main

=== Install

We register the key of the package repository:

  % sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 1BD22CD1

We install milter manager package:

  % sudo aptitude update
  % sudo aptitude -V -D -y install milter-manager

We use Postfix as MTA:

  % sudo aptitude -V -D -y install postfix

We use spamass-milter, clamav-milter and milter-greylist as
milters.

  % sudo aptitude -V -D -y install spamass-milter clamav-milter milter-greylist

== Configuration

Here is a basic configuration policy.

We use UNIX domain socket for accepting connection from
MTA because security and speed.

We set read/write permission for 'postfix' group to UNIX
domain socket because existing milter packages'
configuration can be used.

milter-greylist should be applied only if
((<S25R|URL:http://gabacho.reto.jp/en/anti-spam/>))
condition is matched to reduce needless delivery delay.
But the configuration is automatically done by
milter-manager. We need to do nothing for it.

=== Configure spamass-milter

At first, we configure spamd.

We add the following configuration to
/etc/spamassassin/local.cf. This configuration is for adding
headers only if spam detected.

  report_safe 0

  remove_header ham Status
  remove_header ham Level

We change /etc/default/spamassassin like the following to
enable spamd:

Before:
  ENABLED=0

After:
  ENABLED=1

spamd should be started:

  % sudo /etc/init.d/spamassassin start

There are no changes for spamass-milter's configuration.

=== Configure clamav-milter

We don't need to change the default clamav-milter's configuration.

=== Configure milter-greylist

We change /etc/milter-greylist/greylist.conf for the following
configurations:

  * use the leading 24bits for IP address match to avoid
    Greylist adverse effect for sender uses some MTA case.
  * decrease retransmit check time to 10 minutes from 30
    minutes (default value) to avoid Greylist adverse effect.
  * increase auto whitelist period to a week from 1 day
    (default value) to avoid Greylist adverse effect.
  * use Greylist by default.

  # note
  The configuration relaxes Greylist check to avoid Greylist
  adverse effect. It increases received spam mails but we
  should give priority to avoid false positive rather than
  false negative. We should not consider that we blocks all
  spam mails by Greylist. We can blocks spam mails that
  isn't blocked by Greylist by other anti-spam technique
  such as SpamAssassin. milter manager helps constructing
  mail system that combines some anti-spam techniques.

Before:
  racl whitelist default

After:
  subnetmatch /24
  greylist 10m
  autowhite 1w
  racl greylist default

We change /etc/default/milter-greylist to enable
milter-greylist. milter-greylist uses IPv4 socket because
milter-greylist's run script doesn't support changing
socket's group permission:

Before:
  ENABLED=0

After:
  ENABLED=1
  SOCKET="inet:11125@[127.0.0.1]"

milter-greylist should be started:

  % sudo /etc/init.d/milter-greylist start

=== Configure milter-manager

milter-manager detects milters that installed in system.
We can confirm spamass-milter, clamav-milter and
milter-greylist are detected:

  % sudo /usr/sbin/milter-manager -u milter-manager --show-config

The following output shows milters are detected:

  ...
  define_milter("milter-greylist") do |milter|
    milter.connection_spec = "inet:11125@[127.0.0.1]"
    ...
    milter.enabled = true
    ...
  end
  ..
  define_milter("clamav-milter") do |milter|
    milter.connection_spec = "unix:/var/run/clamav/clamav-milter.ctl"
    ...
    milter.enabled = true
    ...
  end
  ..
  define_milter("spamass-milter") do |milter|
    milter.connection_spec = "unix:/var/spool/postfix/spamass/spamass.sock"
    ...
    milter.enabled = true
    ...
  end
  ..

We should confirm that milter's name, socket path and
'enabled = true'. If the values are unexpected,
we need to change
/etc/milter-manager/milter-manager.conf.
See ((<Configuration|configuration.rd>)) for details of
milter-manager.conf.

But if we can, we want to use milter manager without editing
miter-manager.conf. If you report your environment to the
milter manager project, the milter manager project may
improve detect method.

We change /etc/default/milter-manager to work with Postfix:

Before:
  # For postfix, you might want these settings:
  # SOCKET_GROUP=postfix
  # CONNECTION_SPEC=unix:/var/spool/postfix/milter-manager/milter-manager.sock

After:
  # For postfix, you might want these settings:
  SOCKET_GROUP=postfix
  CONNECTION_SPEC=unix:/var/spool/postfix/milter-manager/milter-manager.sock

We create a directory for milter-manager's socket:

  % sudo mkdir -p /var/spool/postfix/milter-manager/

We add milter-manager user to postfix group:

  % sudo adduser milter-manager postfix

milter-manager's configuration is completed. We start
milter-manager:

  % sudo /etc/init.d/milter-manager restart

/usr/bin/milter-test-server is useful to confirm
milter-manager was ran:

  % sudo -u postfix milter-test-server -s unix:/var/spool/postfix/milter-manager/milter-manager.sock

Here is a sample success output:

  status: accept
  elapsed-time: 0.128 seconds

If milter-manager fails to run, the following message will
be shown:

  Failed to connect to unix:/var/spool/postfix/milter-manager/milter-manager.sock: No such file or directory

In this case, we can use log to solve the
problem. milter-manager is verbosely if --verbose option is
specified. milter-manager outputs logs to standard output if
milter-manager isn't daemon process.

We can add the following configuration to
/etc/default/milter-manager to output verbose log to
standard output:

  OPTION_ARGS="--verbose --no-daemon"

We start milter-manager again:

  % sudo /etc/init.d/milter-manager restart

Some logs are output if there is a problem. Running
milter-manager can be exited by Ctrl+c.

OPTION_ARGS configuration in /etc/default/milter-manager
should be commented out after the problem is solved to run
milter-manager as daemon process. And we should restart
milter-manager.

=== Configure Postfix

We add the following milter configuration to
/etc/postfix/main.cf.

  milter_default_action = accept
  milter_protocol = 6
  milter_mail_macros = {auth_author} {auth_type} {auth_authen}

Here are descriptions of the configuration.

: milter_protocol = 6

   Postfix uses milter protocol version 6.

: milter_default_action = accept

   Postfix accepts a mail if Postfix can't connect to
   milter. It's useful configuration for not stopping mail
   server function if milter has some problems. But it
   causes some problems that spam mails and virus mails may
   be delivered until milter is recovered.

   If you can recover milter, 'tempfail' will be better
   choice rather than 'accept'. Default is 'tempfail'.

: milter_mail_macros = {auth_author} {auth_type} {auth_authen}

   Postfix passes SMTP Auth related information to
   milter. Some milters like milter-greylist use it.

We need to register milter-manager to Postfix. It's
important that spamass-milter, clamav-milter,
milter-greylist aren't needed to be registered because they
are used via milter-manager.

We need to add the following configuration to
/etc/postfix/main.cf. Note that Postfix chrooted to
/var/spool/postfix/.

  smtpd_milters = unix:/milter-manager/milter-manager.sock

We reload Postfix configuration:

  % sudo /etc/init.d/postfix reload

Postfix's milter configuration is completed.

milter-manager logs to syslog. If milter-manager works well,
some logs can be shown in /var/log/mail.info. We need to
sent a test mail for confirming.

== Conclusion

There are many configurations to work milter and Postfix
together. They can be reduced by introducing milter-manager.

Without milter-manager, we need to specify sockets of
spamass-milter, clamav-milter and milter-greylist to
smtpd_milters. With milter-manager, we doesn't need to
specify sockets of them, just specify a socket of
milter-manager. They are detected automatically. We doesn't
need to take care some small mistakes like typo.

milter-manager also supports ENABLED configuration used in
/etc/default/milter-greylist. If we disable a milter, we
use the following steps:

  % sudo /etc/init.d/milter-greylist stop
  % sudo vim /etc/default/milter-greylist # ENABLED=1 => ENABLED=0

We need to reload milter-manager after we disable a milter.

  % sudo /etc/init.d/milter-manager reload

milter-manager detects a milter is disabled and doesn't use
it. We doesn't need to change Postfix's main.cf.

We can reduce maintenance cost by introducing
milter-manager if we use some milters on Debian GNU/Linux.

milter manager also provides tools to help
operation. Installing them is optional but we can reduce
operation cost too. If we also install them, we will go to
((<Install to Debian
(optional)|install-options-to-debian.rd>)).
