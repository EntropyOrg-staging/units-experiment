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

package OOverload;

our $scalar_unit;

sub mangle {
	my ($class, $object, $unit) = @_;

	my $overload_orig_mult = overload::Method($object, '*');
	my $overload_orig_str = overload::Method($object, '""');
	if( $object->isa('PDL') ) {
		# hack
		$overload_orig_str = \&PDL::Core::string;
	}

	use DDP; p $object;
	unless( Moo::Role->does_role($object,  'UnitRole' ) ) {
		Moo::Role->apply_roles_to_object($object, 'UnitRole');
	}
	$object->unit($unit);
	my $overload_new_mult = sub {
		my ($x, $y, $o) = @_;
		my $obj_prod = $overload_orig_mult->(@_);
		my $unit_prod = UnitRole::op_unit_mult(@_); # this should be better
		OOverload->mangle($obj_prod, $unit_prod);
		$obj_prod;
	};

	
	my $overload_new_str = sub {
		my ($x, $o) = @_;
		my $obj_str = $overload_orig_str->(@_);
		"$obj_str~@{[$x->unit]}";
	};
	{
		my $package_of_overload = ref $object;
		# warning!
		eval qq|
		package $package_of_overload;
		use overload '*' => \$overload_new_mult,
			'""' => \$overload_new_str
		|;
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

my $z = $p * $q;

say $z;
