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


1;
