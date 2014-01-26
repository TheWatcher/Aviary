#!/usr/bin/perl

use utf8;
use v5.12;
use lib qw(/var/www/webperl);
use FindBin;

# Work out where the script is, so module and config loading can work.
my $scriptpath;
BEGIN {
    if($FindBin::Bin =~ /(.*)/) {
        $scriptpath = $1;
    }
}

use lib "$scriptpath/modules";

use Webperl::ConfigMicro;
use Webperl::Logger;

use Aviary::System::SheetParser;

use Data::Dumper;

my $logger = Webperl::Logger -> new(syslog => 'Loadtest:')
    or die "FATAL: Unable to create logger object\n";

$logger -> print(Webperl::Logger::NOTICE, "Running schedule loader");

my $parser = Aviary::System::SheetParser -> new(logger => $logger,
                                                minimal => 1)
    or die "FATAL: Unable to create parser object\n";

print "Schedule:\n".Dumper($parser -> load_schedule("/home/chris/perltesting/test.xls",
                                                    0));
