## @file
# This file contains the implementation of the core aviary interface.
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

## @class
package Aviary::Calendar;

use strict;
use experimental qw(smartmatch);
use v5.12;

use base qw(Aviary); # This class extends the Aviary block class
use Webperl::Utils qw(path_join);
use DateTime;


## @method $ build_current_month($pathinfo)
# Determine the currently selected month based on the contents of the
# specified pathinfo array. If the first element of the pathinfo is a
# 4 digit value, it is taken as the year number, and if that is followed
# by a two digit, 01-12 inclusive value, that is taken as the month.
#
# @note This will modify the array referred to by `pathinfo`: if the
#       year is specified, or the year and month, they are removed from
#       the array as part of processing the values. After calling this
#       the array referred to by `pathinfo` will contain values not
#       used by this function.
#
# @param pathinfo A reference to an array of pathinfo values.
# @return Two values: the current year and the current month. If the
#         `pathinfo` array does not explicitly set these, they default
#         to the current year and month.
sub build_current_month {
    my $self     = shift;
    my $pathinfo = shift;
    my $now      = DateTime -> now();

    # Default the values
    my $year  = $now -> year;
    my $month = $now -> month;

    # Years are just four digits; restricting the range is possible, but meeeh.
    if($pathinfo -> [0] && $pathinfo -> [0] =~ /^\d{4}$/) {
        $year = shift(@{$pathinfo});

        # Months must be 01 to 12
        if($pathinfo -> [0] && $pathinfo -> [0] =~ /^(0[1-9]|1[0-2])$/) {
            $month = shift(@{$pathinfo});
        }
    }

    return ($year, $month, $pathinfo);
}


## @method $ get_grid_info($year, $month, $start_monday)
# Given a month and date, build a hash that desribes the dates that
# should be shown in the 6x7 grid of days shown to the user.
#
# @param year         The year containing the current month.
# @param month        The month shown in the calendar.
# @param start_sunday If true, weeks start on Sunday, otherwise the week
#                     will start on Monday.
# @return A reference to a hash containing the date information.
sub get_grid_info {
    my $self  = shift;
    my $year  = shift;
    my $month = shift;
    my $start_sunday = shift;

    # Get a datetime for the first of the month
    my $monthdate = DateTime -> new(year  => $year,
                                    month => $month,
                                    day   => 1);

    # Which day of the week is the first of the month on?
    # Remember to adjust for sun/mon start
    my $start_day = $monthdate -> day_of_week(); # 1 = monday, 7 = sunday
    if($start_sunday) {
        $start_day = $start_day % 7; # 0 = sunday, 1 = monday, 6 = friday
    } else {
        --$start_day; # 0 = monday, 6 = sunday
    }

    # Start building the grid data hash
    my $griddata = { "firstdate" => $monthdate -> clone(),
                     "firstday"  => $start_day };

    # When does the current month end? This is needed to work out when the last day is.
    my $monthend  = $monthdate -> clone() -> add(months => 1) -> subtract(days => 1);

    # Shift back to the start of the grid - this should be the days in the previous
    # month visible before the current one starts.
    $monthdate -> subtract(days => $start_day);

    # Traverse the grid; there are 6 rows of 7 days which will always be enough to
    # show all the days in a month, plus some surround.
    for(my $day = 0; $day < 42; ++$day) {
        # Each day needs a bunch of data associated with it...
        push(@{$griddata -> {"days"}}, {"start"   => $monthdate -> epoch(),  # The start timestamp, for database stuff
                                        "daynum"  => $monthdate -> day(),    # Which day in the month is it for convenience
                                        "month"   => $monthdate -> month(),  # And which month, likewise
                                        "inmonth" => ($monthdate -> month() == $month), # Is this day in the target month?
                                       });

        # work out the last day on the fly, it's less faffing...
        $griddata -> {"lastday"} = $day
            if($monthdate == $monthend);

        # And move to the next day
        $monthdate -> add(days => 1);
    }

    return $griddata;
}


## @method private $ _generate_day_names($start_sunday)
# Generate the headers containing the day names.
#
# @param start_sunday If true, weeks start on Sunday, otherwise the week
#                     will start on Monday.
# @return A string containing the day name headers.
sub _generate_day_names {
    my $self         = shift;
    my $start_sunday = shift;
    my $days         = "";

    foreach my $day (1..7) {
        my $name = $self -> {"template"} -> replace_langvar("CALENDAR_DAY".($start_sunday ? (($day + 6) % 7) + 1 : $day));
        $days .= $self -> {"template"} -> load_template("calendar/daynames.tem", {"{T_[id]}"   => "day_".($day - 1),
                                                                                  "{T_[name]}" => $name});
    }

    return $days;
}


## @method private @ _generate_calendar_page($year, $month)
# Generate the calendar body for the specified year and month.
#
# @param year         The year to generate the calendar for.
# @param month        The month to generate the calendar for.
# @param start_sunday If true, weeks start on Sunday, otherwise the week
#                     will start on Monday.
# @return Up to three values: the page title, content, and extra header.
sub _generate_calendar_page {
    my $self  = shift;
    my $year  = shift;
    my $month = shift;
    my $start_sunday = shift;

    my $grid = $self -> get_grid_info($year, $month, $start_sunday);
    my $id = 0;
    my $weeks = "";
    foreach my $week (0..5) {
        my $days = "";
        foreach my $day (0..6) {
            $days = $self -> {"template"} -> load_template("calendar/day.tem", { "{T_[dayid]}"    => $id,
                                                                                 "{T_[dayclass]}" => $grid -> {"days"} -> [$id] -> {"inmonth"} ? "inmonth" : "outmonth",
                                                                                 "{T_[daynum]}"   => $grid -> {"days"} -> [$id] -> {"daynum"},
                                                           });
            ++$id;
        }
        $weeks .= $self -> {"template"} -> load_template("calendar/week.tem", {"{T_[days]}" => $days});
    }

    return $self -> {"template"} -> load_template("calendar/content.tem", {"{T_[monthname]}" => $grid -> {"startdate"} -> month_name(),
                                                                           "{T_[year]}"      => $year,1
                                                                           "{T_[month]}"     => $month,
                                                                           "{T_[daynames]}"  => $self -> _generate_day_names($start_sunday),
                                                                           "{T_[weeks]}"     => $weeks,
                                                  });
}




# ============================================================================
#  Interface functions

## @method $ page_display()
# Produce the string containing this block's full page content. This generates
# the compose page, including any errors or user feedback.
#
# @return The string containing this block's page content.
sub page_display {
    my $self = shift;
    my ($title, $content, $extrahead);

    my $error = $self -> check_login();
    return $error if($error);

    # Is this an API call, or a normal page operation?
    my $apiop = $self -> is_api_operation();
    if(defined($apiop)) {
        # API call - dispatch to appropriate handler.
        given($apiop) {
            default {
                return $self -> api_html_response($self -> api_errorhash('bad_op',
                                                                         $self -> {"template"} -> replace_langvar("API_BAD_OP")))
            }
        }
    } else {
        my @pathinfo = $self -> {"cgi"} -> param('pathinfo');
        my ($year, $month) = $self -> build_current_month(\@pathinfo);

        ($title, $content, $extrahead) = $self -> _generate_calendar_page($year, $month, 1);

        $extrahead .= $self -> {"template"} -> load_template("calendar/extrahead.tem");
        return $self -> generate_aviary_page($title, $content, $extrahead);
    }
}

1;
