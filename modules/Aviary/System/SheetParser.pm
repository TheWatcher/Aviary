## @file
# This file contains the implementation of the metadata handling engine.
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
#
package Aviary::System::SheetParser;

use strict;
use base qw(Webperl::SystemModule);

use Spreadsheet::ParseExcel;
use Spreadsheet::ParseExcel::FmtUTF8;
use Spreadsheet::ParseExcel::Utility qw(ExcelLocaltime);
use DateTime;


# ==============================================================================
# Public interface

## @method $ load_schedule($bookname, $sheetname)
# Parse the schedule out of the specified worksheet in the excel
# workbook, and return an array containing the schedule data.
#
# @param bookname  The filename of the excel workbook to parse the
#                  data from. This can also be a filehandle or
#                  a scalar reference.
# @param sheetname The name (or number) of the worksheet in the
#                  workbook that contains the schedule data.
# @return A reference to an array of hashes, each hash is a day
#         and it contains the date and a time-keyed hash of tweets.
#         Returns undef on error.
sub load_schedule {
    my $self      = shift;
    my $bookname  = shift;
    my $sheetname = shift;
    my $parser    = Spreadsheet::ParseExcel -> new();

    $self -> clear_error();

    # Parse the specified workbook
    my $workbook = $parser -> parse($bookname, Spreadsheet::ParseExcel::FmtUTF8 -> new());
    return $self -> self_error("Unable to parse spreadsheet '$bookname': ".$parser -> error())
        if(!defined($workbook));

    # Now try to get the worksheet
    my $worksheet = $workbook -> worksheet($sheetname);
    return $self -> self_error("Requested worksheet does not exist")
        if(!defined($worksheet));

    return $self -> _extract_schedule($worksheet);
}


# ==============================================================================
# Private methods

## @method private $ _extract_schedule($worksheet)
# Performs the actual extraction of the scheduled tweets from the specified
# worksheet. This looks for dates with defined tweet lists, and constructs a
# list of hashes, one hash per day, storing the date and list of tweets for
# that day as a time-keyed hash.
#
# @param worksheet The worksheet to extract the schedule from.
# @return A reference to an array of hashes, one per day, containing the
#         date and time-keyed hash of tweets. If the sheet contains no
#         scheduled tweets, this returns an empty list.
sub _extract_schedule {
    my $self      = shift;
    my $worksheet = shift;
    my $schedule  = [];
    my $datecell  = {};

    # Scan the sheet, once cell at a time, looking for cels that look like dates. This fetches the
    # cell location and a reference to the cell, the body of the loop processes it and updates the
    # column so that the search can continue from just after where it left off.
    while($datecell = $self -> _find_datecell($worksheet, $datecell -> {"col"}, $datecell -> {"row"})) {

        # Get the list of defined tweets for this date, if any
        my $tweets = $self -> _find_tweetlist($worksheet, $datecell -> {"col"}, $datecell -> {"row"});

        # Record the tweet list if any have been found for this date
        push(@{$schedule}, { "date"   => $self -> _local_to_datetime(ExcelLocaltime($datecell -> {"cell"} -> unformatted())),
                             "tweets" => $tweets
                           }
            )
            if($tweets);

        # Move to the next cell to the right
        ++$datecell -> {"col"};
    }

    return $schedule;
}


## @method private $ _find_datecell($sheet, $col, $row)
# Locate a cell in the specified sheet that looks like a date cell. This
# scans the sheet looking for the next cell that looks like a date from
# the specified row and column.
#
# @param sheet The worksheet to search for a date cell
# @param col   The column to start searching from. If this is not defined,
#              the minimum column is used by default.
# @param row   The row to start searching from. If not defined, the minimum
#              row is used.
# @return If a date cell is found, this returns a reference to a hash
#         containing the col, row, and cell. If no date cells are found,
#         this returns undef.
sub _find_datecell {
    my $self  = shift;
    my $sheet = shift;
    my $col   = shift;
    my $row   = shift;

    my ( $r_min, $r_max ) = $sheet -> row_range();
    my ( $c_min, $c_max ) = $sheet -> col_range();

    # Make sure that x and y are within range
    $col = $c_min if(!defined($col) || $col < $c_min);
    $row = $r_min if(!defined($row) || $row < $r_min);

    for(; $row <= $r_max; ++$row) {
        for(; $col <= $c_max; ++$col) {
            my $cell = $sheet -> get_cell($row, $col);
            next unless($cell);

            # Is the cell a date cell?
            return {"col" => $col, "row" => $row, "cell" => $cell }
                if($cell -> value() =~ /^\d+-\w{3}$/);
        }
        $col = $c_min;
    }

    return undef;
}


## @method private $ _get_tweet_time($sheet, $col, $row)
# Given a sheet and cell location, determine whether the cell at that location
# appears to be a time, and if it is return the time string. This checks
# whether the cell at (col,row) in the specified sheet contains something that
# looks like a 24-hour format time.
#
# @param sheet The worksheet containing the tweet time
# @param col   The column the tweet time should be in.
# @param row   The row the tweet time should be in.
# @return A string containing the tweet time if the cell contains one, undef
#         if the column or row are not valid, or the cell at (col, row) is
#         not a time.
sub _get_tweet_time {
    my $self  = shift;
    my $sheet = shift;
    my $col   = shift;
    my $row   = shift;
    my $cell  = $sheet -> get_cell($row, $col);

    return undef if(!$cell);
    return ""    if($cell -> value() !~ /^\d+:\d+$/);
    return $cell -> value();
}


## @method private $ _get_tweet_text($sheet, $col, $row)
# Fetch the tweet text stored in the cell at the specified column and row.
#
# @param sheet The worksheet containing the tweet.
# @param col   The column the tweet should be in.
# @param row   The row the tweet should be in.
# @return A string containing the tweet if the cell contains one, undef
#         if the column or row are not valid.
sub _get_tweet_text {
    my $self  = shift;
    my $sheet = shift;
    my $col   = shift;
    my $row   = shift;
    my $cell  = $sheet -> get_cell($row, $col);

    # Hald if no cell, or cell contains a date
    return undef if(!$cell || $cell -> value() =~ /^\d+-\w+$/);

    # filled cells should not be handled
    return "" if($cell -> get_format() -> {"Fill"} -> [0]);

    return $cell -> value();
}


## @method private $ _find_tweetlist($sheet, $datecol, $daterow)
# Given the location of a date cell in the specified sheet, pull out any tweets
# scheduled to go out on that date from the surrounding sheet.
#
# @param sheet The worksheet containing the tweet data.
# @param datecol The column containing the date cell.
# @param daterow The row containing the date cell.
# @return A reference to a hash containing time => [tweets] if any tweets
#         have been set fot the specified date, undef otherwise.
sub _find_tweetlist {
    my $self    = shift;
    my $sheet   = shift;
    my $datecol = shift;
    my $daterow = shift;

    # Times start on the row below the date, one column left.
    my $timerow  = $daterow + 1;
    my $timecol  = $datecol - 1;
    my $tweetcol = $datecol; # Tweets are below the date

    my $tweets = {};
    while(1) {
        my $time = $self -> _get_tweet_time($sheet, $timecol, $timerow);
        last unless(defined($time));

        my $tweet = $self -> _get_tweet_text($sheet, $tweetcol, $timerow);
        last unless(defined($tweet));

        # Allow multiple tweets with the same time.
        push(@{$tweets -> {$time}}, $tweet)
            if($time && $tweet);

        ++$timerow;
    }

    my $tcount = keys %{$tweets};
    return $tcount ? $tweets : undef;
}


## @method private $ _local_to_datetime($sec, $min, $hour, $day, $month, $year, $wday, $msec)
# Convert values obtained from ExcelLocaltime into a DateTime object.
#
# @return A reference to a new DateTime object.
sub _local_to_datetime {
    my $self = shift;
    my ($sec, $min, $hour, $day, $month, $year, $wday, $msec) = @_;

    return DateTime -> new(year   => $year + 1900,
                           month  => $month + 1,
                           day    => $day,
                           hour   => $hour,
                           minute => $min,
                           second => $sec,
                           time_zone => "Europe/London");
}

1;
