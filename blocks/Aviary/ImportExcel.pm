## @file
# This file contains the implementation of the aviary import interface.
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
package Aviary::ImportExcel;

use strict;
use base qw(Aviary); # This class extends the Aviary block class
use v5.12;
use Webperl::Utils qw(path_join);
use Aviary::System::SheetParser;
use Data::Dumper;

# ============================================================================
#  Content generators

## @method private @ _generate_import($error)
# Generate the page content for a import page.
#
# @param error An optional error message to display above the form if needed.
# @return Two strings, the first containing the page title, the second containing the
#         page content.
sub _generate_upload {
    my $self  = shift;
    my $error = shift;

    my $userid = $self -> {"session"} -> get_session_userid();

    # Wrap the error in an error box, if needed.
    $error = $self -> {"template"} -> load_template("error/error_box.tem", {"***message***" => $error})
        if($error);

    return ($self -> {"template"} -> replace_langvar("IMPORT_TITLE"),
            $self -> {"template"} -> load_template("import/content.tem", {"***errorbox***" => $error })
           );
}


sub _generate_success {
    my $self    = shift;
    my $removed = shift;
    my $added   = shift;

    my $url = $self -> build_url(pathinfo => [],
                                 api      => [],
                                 params   => {});

    my $content = $self -> {"template"} -> message_box($self -> {"template"} -> replace_langvar("IMPORT_SUCCESS"),
                                                       "imported",
                                                       $self -> {"template"} -> replace_langvar("IMPORT_SUMMARY"),
                                                       $self -> {"template"} -> replace_langvar("IMPORT_LONGDESC", {"***url***"     => $url,
                                                                                                                    "***removed***" => $removed,
                                                                                                                    "***added***"   => $added}),
                                                       undef,
                                                       "successbox",
                                                       [ {"message" => $self -> {"template"} -> replace_langvar("SITE_CONTINUE"),
                                                          "colour"  => "blue",
                                                          "action"  => "location.href='$url'"} ]);
    my $extrahead = $self -> {"template"} -> load_template("refreshmeta.tem", {"***url***" => $url});

    return ($self -> {"template"} -> replace_langvar("IMPORT_SUCCESS"), $content, $extrahead);
}



# ============================================================================
#  Validation and workers

## @method private @ _validate_upload()
# Validate the excel file submission from the user, and attempt to update the
# schedule if it is valid.
#
# @return Two strings, the first containing the page title, the second containing the
#         page content.
sub _validate_upload {
    my $self   = shift;
    my $errors = shift;
    my $userid = $self -> {"session"} -> get_session_userid();

    my $filename = $self -> {"cgi"} -> param("excelfile");
    return $self -> _generate_upload("{L_IMPORT_ERR_NOFILESET}")
        if(!$filename);

    my $filehandle = $self -> {"cgi"} -> upload("excelfile");
    return $self -> _generate_upload("{L_IMPORT_ERR_BADHANDLE}")
        if(!$filehandle);

    my $parser = Aviary::System::SheetParser -> new(logger  => $self -> {"logger"},
                                                    minimal => 1)
        or return $self -> _generate_upload("{L_IMPORT_ERR_BADPARSER}");

    # Always parse the first sheet.
    # FIXME: allow a way to select sheets.
    my $schedule = $parser -> load_schedule($filehandle, 0)
        or return $self -> _generate_upload($parser -> errstr());

    # Get rid of unposted scheduled messages
    my $removed = $self -> {"system"} -> {"schedule"} -> clear_unposted($userid, "import");
    return $self -> _generate_upload($self -> {"system"} -> {"schedule"} -> errstr())
        if(!defined($removed));

    # Import the new messages
    my $added = $self -> {"system"} -> {"schedule"} -> import_schedule($schedule, $userid, "import");
    return $self -> _generate_upload($self -> {"system"} -> {"schedule"} -> errstr())
        if(!defined($added));

    return $self -> _generate_success($removed, $added);
}


# ============================================================================
#  Interface functions

## @method $ page_display()
# Produce the string containing this block's full page content. This generates
# the import page, including any errors or user feedback.
#
# @return The string containing this block's page content.
sub page_display {
    my $self = shift;
    my ($title, $content, $extrahead);

    my $error = $self -> check_login();
    return $error if($error);

    # Exit with a permission error unless the user has permission to import
    if(!$self -> check_permission("import")) {
        $self -> log("error:import:permission", "User does not have permission to import schedules");

        my $userbar = $self -> {"module"} -> load_module("Aviary::Userbar");
        my $message = $self -> {"template"} -> message_box("{L_PERMISSION_FAILED_TITLE}",
                                                           "error",
                                                           "{L_PERMISSION_FAILED_SUMMARY}",
                                                           "{L_PERMISSION_IMPORT_DESC}",
                                                           undef,
                                                           "errorcore",
                                                           [ {"message" => $self -> {"template"} -> replace_langvar("SITE_CONTINUE"),
                                                              "colour"  => "blue",
                                                              "action"  => "location.href='".$self -> build_url(block => "import", pathinfo => [])."'"} ]);

        return $self -> {"template"} -> load_template("error/general.tem",
                                                      {"***title***"     => "{L_PERMISSION_FAILED_TITLE}",
                                                       "***message***"   => $message,
                                                       "***extrahead***" => "",
                                                       "***userbar***"   => $userbar -> block_display("{L_PERMISSION_FAILED_TITLE}"),
                                                      })
    }

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
        if(defined($self -> {"cgi"} -> param("import"))) {
            ($title, $content, $extrahead) = $self -> _validate_upload();
        } else {
            ($title, $content, $extrahead) = $self -> _generate_upload();
        }

        $extrahead .= $self -> {"template"} -> load_template("import/extrahead.tem");
        return $self -> generate_aviary_page($title, $content, $extrahead);
    }
}

1;
