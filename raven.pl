#!/usr/bin/perl

use v5.12;
use Proc::Daemon;
use FindBin;
use List::Util qw(min);
use DateTime;

use lib qw(/var/www/webperl);
use Webperl::ConfigMicro;
use Webperl::Daemon;
use Webperl::Logger;
use Webperl::Utils qw(path_join);

# Work out where the script is, so module and config loading can work.
my $scriptpath;
BEGIN {
    if($FindBin::Bin =~ /(.*)/) {
        $scriptpath = $1;
    }
}

use lib "$scriptpath/modules";
use Aviary::System::Schedule;
use Net::Twitter::Lite::WithAPIv1_1;


## @fn void schedule_wait($logger, $settings, $schedule)
# Wait until the next scheduled post time.
#
# @param logger   A reference to the system logger object.
# @param settings A reference to the system settings.
# @param schedule A reference to an Aviary::System::Schedule object to check
#                 the schedule through.
sub schedule_wait {
    my $logger   = shift;
    my $settings = shift;
    my $schedule = shift;
    my $now      = time();

    # Determine how long the process should wait for.
    my $wakeup = $schedule -> get_next_schedule_time($now);
    if($wakeup) {
        my $next_schedule = DateTime -> from_epoch(epoch => $wakeup);
        $logger -> print(Webperl::Logger::NOTICE, "Next scheduled message is at $next_schedule");

        $wakeup = min($wakeup - $now, $settings -> {"raven"} -> {"default_sleep"})
    } else {
        $wakeup = $settings -> {"raven"} -> {"default_sleep"};
    }

    $logger -> print(Webperl::Logger::NOTICE, "Sleeping for $wakeup seconds");

    # This sleep should be interrupted if the schedule is updated
    sleep($wakeup);
}


# @param logger   A reference to the system logger object.
# @param settings A reference to the system settings.
# @param schedule A reference to an Aviary::System::Schedule object to check
#                 the schedule through.
# @param twitter  A reference to a Net::Twitter::Lite object to post to twitter through.
sub post_schedule {
    my $logger   = shift;
    my $settings = shift;
    my $schedule = shift;
    my $twitter  = shift;

    $logger -> print(Webperl::Logger::NOTICE, "Checking for pending messages");

    my $to_post = $schedule -> get_pending_scheduled()
        or $logger -> die_log("Scheduler failed: ".$schedule -> errstr());

    $logger -> print(Webperl::Logger::NOTICE, "Got ".scalar(@{$to_post})." pending messages");

    foreach my $message (@{$to_post}) {
        $message -> {"tweet"} =~ s/[\#\@]//g;
        $logger -> print(Webperl::Logger::NOTICE, "Posting ".$message -> {"id"}." = ".$message -> {"tweet"});

        eval { $twitter -> update($message -> {"tweet"}); };
        $logger -> die_log("Tweet failed: $@")
            if($@);

        $schedule -> mark_as_posted($message -> {"id"})
            or $logger -> die_log("Scheduler failed: ".$schedule -> errstr());
    }
}


my $logger = Webperl::Logger -> new(syslog => 'Raven:')
    or die "FATAL: Unable to create logger object\n";

my $settings = Webperl::ConfigMicro -> new(path_join($scriptpath, "config", "site.cfg"))
    or $logger -> die_log("FATAL: Unable to load config: ".$Webperl::SystemModule::errstr);

my $daemon = Webperl::Daemon -> new(pidfile => $settings -> {"raven"} -> {"pidfile"});
$daemon -> run('start');

$logger -> print(Webperl::Logger::NOTICE, "Started background Twitter poster");

my $dbh = DBI->connect($settings -> {"database"} -> {"database"},
                       $settings -> {"database"} -> {"username"},
                       $settings -> {"database"} -> {"password"},
                       { RaiseError => 0, AutoCommit => 1, mysql_enable_utf8 => 1 })
    or $logger -> die_log("Unable to connect to database: ".$DBI::errstr);

my $schedule = Aviary::System::Schedule -> new(logger   => $logger,
                                               settings => $settings,
                                               dbh      => $dbh)
    or $logger -> die_log($Webperl::SystemModule::errstr);

my $twitter = Net::Twitter::Lite::WithAPIv1_1 -> new(consumer_key        => $settings -> {"twitter"} -> {"consumer_key"},
                                                     consumer_secret     => $settings -> {"twitter"} -> {"consumer_secret"},
                                                     access_token        => $settings -> {"twitter"} -> {"access_token"},
                                                     access_token_secret => $settings -> {"twitter"} -> {"token_secret"},
                                                     ssl                 => 1,
                                                     wrap_result         => 1);

# Make the default alarm handler ignore the signal. This should still make sleep() wake, though.
$SIG{"ALRM"} = sub { $logger -> print(Webperl::Logger::NOTICE, "Received alarm signal") };

while(1) {
    post_schedule($logger, $settings, $schedule, $twitter);
    schedule_wait($logger, $settings, $schedule);
}
