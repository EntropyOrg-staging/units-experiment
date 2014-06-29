#!/usr/bin/env perl

use strict;
use warnings;
use v5.16;

package UnitHandler;

use overload '*' => "op_mult",
	'""' => 'op_stringify';


use Moo;

has data => ( is => 'rw' );

has unit => ( is => 'rw' );

sub op_mult {
	my ($x, $y, $o) = @_;
	my $data_prod = $x->data * $y->data;
	my $unit_prod = "@{[$x->unit]}*@{[$y->unit]}";
	UnitHandler->new( data => $data_prod, unit => $unit_prod );
}

sub op_stringify {
	my ($x, $o) = @_;
	my $data_str = ~~ ($x->data);
	my $unit_str = ~~ ($x->unit);
	"$data_str~$unit_str";
}

package main;

use PDL;

my $d = UnitHandler->new( data => pdl(q[4 2]) , unit => 'm' );
my $t = UnitHandler->new( data => pdl(q[3 3]) , unit => 's' );

my $dt = $d * $t;

say "$d * $t = $dt";

use DDP; p overload::Method($d, '*');
