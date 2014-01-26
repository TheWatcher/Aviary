# @file
# This file contains the implementation of the aviary schedule model.
#
# @author  Chris Page &lt;chris@starforge.co.uk&gt;
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
package Aviary::System::Schedule;

use strict;
use base qw(Webperl::SystemModule);
use v5.12;


## @method $ clear_unposted($userid, $source)
# Clear any unposted messages in the schedule for the specified user that
# were added via the named source.
#
# @param userid The ID of the user to remove unposted messages for.
# @param source The name of the data source to remove messages for.
# @return The number of removed items on success (which may be zero),
#         undef on error.
sub clear_unposted {
    my $self   = shift;
    my $userid = shift;
    my $source = shift;

    my $nukeh = $self -> {"dbh"} -> prepare("DELETE FROM `".$self -> {"settings"} -> {"database"} -> {"schedule"}."`
                                             WHERE creator_id = ?
                                             AND source LIKE ?
                                             AND posted IS NULL");
    my $rows = $nukeh -> execute($userid, $source);
    return $self -> self_error("Unable to remove unposted scheduled messages: ".$self -> {"dbh"} -> errstr) if(!$rows);

    $rows = 0 if($rows eq "0E0");
    return $rows;
}


## @method $ import_schedule($schedule, $userid, $source, $incpast)
# Import the messages in the specified schedule, marking them as owned by
# the specified user and coming from the provided source.
#
# @param schedule A reference to an array of schedule hashes, as returned
#                 by Aviary::System::SheetParser::load_schedule()
# @param userid   The ID of the user to attribute the messages to.
# @param source   The source name to attach to the messages
# @param incpast  If set to true, messages are scheduled even though they
#                 are at a time or date in the past.
# @return The number of added messages on success, undef on error.
sub import_schedule {
    my $self     = shift;
    my $schedule = shift;
    my $userid   = shift;
    my $source   = shift;
    my $incpast  = shift;
    my $added    = 0;
    my $now      = time();

    # This query will be used a lot, so prepare in advance
    my $schedh = $self -> {"dbh"} -> prepare("INSERT INTO `".$self -> {"settings"} -> {"database"} -> {"schedule"}."`
                                              (`post_at`, `added`, `creator_id`, `edited`, `editor_id`, `source`, `tweet`)
                                              VALUES(?, UNIX_TIMESTAMP(), ?, UNIX_TIMESTAMP(), ?, ?, ?)");

    # The schedule arrayref contains a list of days
    foreach my $day (@{$schedule}) {

        # Each day contains a DateTime object and a list of hash of tweet lists, keyed by time
        foreach my $time (keys(%{$day -> {"tweets"}})) {
            my ($hour, $minute) = $time =~ /^(\d+):(\d+)$/;

            # This check *should* be redundant, but do it anyway: only handle valid times
            if(defined($hour) && defined($minute)) {
                # Just use the DateTime object in the day for the tweet time and day
                $day -> {"date"} -> set(hour => $hour, minute => $minute);

                # Only add messages due to be posted in TEH FUTURE, unless past inclusion is enabled
                my $postat = $day -> {"date"} -> epoch();
                next unless($incpast || $postat > $now);

                # Process the list of tweets for the current time and day.
                foreach my $tweet (@{$day -> {"tweets"} -> {$time}}) {
                    $schedh -> execute($postat, $userid, $userid, $source, $tweet)
                        or return $self -> self_error("Failed to add ".$day -> {"date"}.":$tweet to schedule: ".$self -> {"dbh"} -> errstr);

                    ++$added;
                }
            }
        }
    }

    return $added;
}

1;
