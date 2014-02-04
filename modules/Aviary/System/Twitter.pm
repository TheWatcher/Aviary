## @file
#
# This file contains the implementation of the aviary twitter wrapper
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
package Aviary::System::Twitter;

use strict;
use base qw(Webperl::SystemModule);
use v5.12;
use Net::Twitter::Lite::WithAPIv1_1;

## @method $ get_twitter($userid)
# Get the twitter handle for the user with the specified id.
#
# @param userid The user to fetch the twitter handle for.
# @return A reference to a Net::Twitter::Lite object on success,
#         undef on error.
sub get_twitter {
    my $self   = shift;
    my $userid = shift;

    $self -> clear_error();

    # return the cached handle if there is one
    return ($self -> {"handles"} -> {$userid})
        if($self -> {"handles"} -> {$userid});

    # Otherwise, we need to make one. Fetch the user's settings from the database.
    my $userh = $self -> {"dbh"} -> prepare("SELECT *
                                             FROM `".$self -> {"settings"} -> {"database"} -> {"twittercfg"}."`
                                             WHERE `user_id` = ?");
    $userh -> execute($userid)
        or return $self -> self_error("Unable to execute user twitter lookup query: ".$self -> {"dbh"} -> errstr);

    my $user = $userh -> fetchrow_hashref()
        or return $self -> self_error("Request for settings for user $userid with no defined twitter config");

    $self -> {"handles"} -> {$userid} = Net::Twitter::Lite::WithAPIv1_1 -> new(consumer_key        => $user -> {"consumer_key"},
                                                                               consumer_secret     => $user -> {"consumer_secret"},
                                                                               access_token        => $user -> {"access_token"},
                                                                               access_token_secret => $user -> {"token_secret"},
                                                                               ssl                 => 1,
                                                                               wrap_result         => 1);
    return $self -> {"handles"} -> {$userid};
}

1;
