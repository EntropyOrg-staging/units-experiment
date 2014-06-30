#!/usr/bin/env perl

use strict;
use warnings;
use v5.16;

#package Data::Perl::Number;
#use overload '0+' => sub { ${$_[0]} };
#use overload '""' => sub { ${$_[0]} };

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


package PDL::UnitRole;

use Moo::Role;
use Data::Perl qw(number);
use Scalar::Util;

around qw(sumover cumusumover avg sum) => sub {
	my $orig = shift;
	my ($self) = @_;
	my $ret = $orig->(@_);
	if( !ref $ret and Scalar::Util::looks_like_number($ret) ) {
		$ret = number($ret);
	}
	OOverload->mangle($ret, $self->unit); # propagates
};

package Unit;

use Carp;

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
	confess "Units not compatible: @{[$x->unit]} != @{[$y->unit]}" unless $x->unit eq $y->unit;
	$x->unit;
}

sub op_unit_sub {
	&op_unit_add;
}

package OOverload;

our $OVERLOADED;
use Scalar::Util;

sub mangle {
	my ($class, $object, $unit) = @_;


	unless( exists $OVERLOADED->{ ref $object } ) { # it already has UnitRole
		Moo::Role->apply_roles_to_object($object, 'UnitRole');
		if( $object->isa('PDL') ) {
			Moo::Role->apply_roles_to_object( $object, 'PDL::UnitRole' );;
		}
	}

	$object->unit($unit);

	my $package_of_overload = ref $object;
	unless( exists $OVERLOADED->{ $package_of_overload } ) {
		my %new_ops;
		my %op_table = ( # these should be better
			'+' => \&Unit::op_unit_add,
			'-' => \&Unit::op_unit_sub,
			'*' => \&Unit::op_unit_mult,
			'/' => \&Unit::op_unit_div,
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
		#} elsif( $object->isa('Data::Perl::Number') ) {
			#$overload_orig_str = sub {
				#overload::StrVal( ${ $_[0] } );
			#};
		} elsif( not defined $overload_orig_str ) {
			# last resort
			# does it numify?
			my $scalar_fallback =  sub {
				my ($x) = @_;
				if( Scalar::Util::reftype($x) eq 'SCALAR' ) {
					overload::StrVal($$x);
				} elsif( Scalar::Util::reftype($x) eq 'REF' ) {
					overload::StrVal($$x);
				} else {
					&overload::StrVal;
				}
			};

			$overload_orig_str = overload::Method($object, '0+') // $scalar_fallback;
		}
		my $overload_new_str = sub {
			my ($x, $o) = @_;
			my $obj_str = $overload_orig_str->(@_);
			"$obj_str~@{[$x->unit]}";
		};
		{
			# warning!
			eval qq|
			package $package_of_overload;
			use overload \%new_ops,
				'""' => \$overload_new_str;
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

say "$p / $q = @{[$p / $q]}";

say $p->sumover;
say $p->cumusumover;


say "--\nData::Perl::Number --- bug territory";
my $gg = $p->avg;
say $gg;
say overload::Method($gg, '""')->($gg);

eval {
	my $g = $z + $p;
} or print "can't add: $@\n";
