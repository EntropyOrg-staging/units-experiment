#!/usr/bin/env perl

use strict;
use warnings;
use v5.16;

use DateTime;
say "DateTime @{[ does_it_stringify( DateTime->now ) ]} stringify";
say DateTime->now;

say "----";

use PDL;
say "PDL @{[ does_it_stringify( pdl() ) ]} stringify";
say pdl();

sub does_it_stringify {
	defined overload::Method( $_[0] , '""' ) ? "does" : "does not";
}
