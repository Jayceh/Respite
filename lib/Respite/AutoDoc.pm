use strict;
use warnings;
package Respite::AutoDoc;

use CGI::Ex::App qw(:App);
use base qw(CGI::Ex::App);

use Debug;
use Throw qw(throw);
use Time::HiRes ();
use JSON ();
use Scalar::Util ();

1;
