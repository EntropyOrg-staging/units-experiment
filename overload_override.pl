#!/usr/bin/env perl

use strict;
use warnings;
use v5.16;

package UnitRole;
use Moo::Role;
use Scalar::Util;

sub unit {
	my ($self, $unit) = @_;
	state $_unit; # table to provide inside-out attribute
	if( defined $unit ) {
		$_unit->{ Scalar::Util::refaddr $self } = $unit;
	}
	$_unit->{ Scalar::Util::refaddr $self };
}

sub op_unit_mult {
	my ($x, $y, $o) = @_;
	my $unit_prod = "@{[$x->unit]}*@{[$y->unit]}";
}

sub op_unit_div {
	my ($x, $y, $o) = @_;
	my $unit_prod = "@{[$x->unit]}/@{[$y->unit]}";
}

sub op_unit_add {
	my ($x, $y, $o) = @_;
	die "Units not compatible: @{[$x->unit]} != @{[$y->unit]}" unless $x->unit eq $y->unit;
	$x->unit;
}

sub op_unit_sub {
	&op_unit_add;
}


package OOverload;

our $OVERLOADED;

sub mangle {
	my ($class, $object, $unit) = @_;


	unless( exists $OVERLOADED->{ ref $object } ) {
		Moo::Role->apply_roles_to_object($object, 'UnitRole');
	}

	$object->unit($unit);

	my $package_of_overload = ref $object;
	unless( exists $OVERLOADED->{ $package_of_overload } ) {
		my %new_ops;
		my %op_table = ( # these should be better
			'+' => \&UnitRole::op_unit_add,
			'-' => \&UnitRole::op_unit_sub,
			'*' => \&UnitRole::op_unit_mult,
			'/' => \&UnitRole::op_unit_div,
		);
		for my $op (keys %op_table) {
			my $op_func = $op_table{$op};
			my $op_overload_orig = overload::Method($object, $op);
			$new_ops{$op} = sub {
				my ($x, $y, $o) = @_;
				my $obj_res = $op_overload_orig->(@_);
				my $unit_res = $op_func->(@_);
				OOverload->mangle($obj_res, $unit_res);
			};
		}

		my $overload_orig_str = overload::Method($object, '""');
		if( $object->isa('PDL') ) {
			# hack
			$overload_orig_str = \&PDL::Core::string;
		} elsif( not defined $overload_orig_str ) {
			# last resort
			$overload_orig_str = \&overload::StrVal;
		}
		my $overload_new_str = sub {
			my ($x, $o) = @_;
			my $obj_str = $overload_orig_str->(@_);
			"$obj_str~@{[$x->unit]}";
		};

		my $rest = sub {
			#$a, 3, 1, '+'
		};
		{
			# warning!
			eval qq|
			package $package_of_overload;
			use overload \%new_ops,
				'""' => \$overload_new_str
			|;
		}
		$OVERLOADED->{ $package_of_overload } = 1;
	}

	$object;
}

package main;

use PDL;

my $p = pdl q[4 2];
my $q = pdl q[2 3];

OOverload->mangle( $p, 'm' );
OOverload->mangle( $q, 's' );

say $p;
say $q;

my $y = OOverload->mangle( pdl(q[2 2]) , 'm*s' );

my $z = $p * $q;
say "$p * $q = $z";

say "$z + $y = @{[$z + $y]}";

eval {
	my $g = $z + $p;
} or print "can't add: $@\n";
