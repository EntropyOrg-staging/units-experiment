#!/usr/bin/env perl

use strict;
use warnings;
use v5.18;

package UnitRole;
use Moo::Role;
use Scalar::Util;

sub unit {
	my ($self, $unit) = @_;
	state $_unit; # table to provide inside-out attribute
	if( defined $unit ) {
		$_unit->{ Scalar::Util::refaddr $self } = $unit;
	}
	$_unit->{ Scalar::Util::refaddr $self } // '';
}

sub is_unit_dimensionless {
	my ($self) = @_;
	$self->unit eq '';
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
	my @prod = ( ($x->unit)x!!( not $x->is_unit_dimensionless ),
		($y->unit)x!!( not $y->is_unit_dimensionless ) );
	my $unit_prod = join "*", @prod;
}

sub op_unit_div {
	my ($x, $y, $o) = @_;
	my @prod = ( ($x->unit)x!!( not $x->is_unit_dimensionless ),
		($y->unit)x!!( not $y->is_unit_dimensionless ) );
	my $unit_prod = join "/", @prod;
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
use Package::Stash;

sub mangle {
	my ($class, $object, $unit) = @_;


	my @roles;
	push @roles, 'UnitRole';
	push @roles, 'PDL::UnitRole' if $object->isa('PDL');
	my $role_class = Moo::Role->create_class_with_roles(ref $object, @roles);
	#unless( $object->can('unit') ) { # it already has UnitRole
	unless( exists $OVERLOADED->{ ref $object } ) { # it already has UnitRole
		Moo::Role->apply_roles_to_object( $object, @roles );;
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
				if( Scalar::Util::reftype($x) =~ /^(SCALAR|REF)$/ ) {
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
			#print "--$package_of_overload--\n";#DEBUG
			eval qq|
			package $package_of_overload;
			use overload \%new_ops,
				'""' => \$overload_new_str;
			|;
		}
		$OVERLOADED->{ $package_of_overload } = 1;
	}

	overload::Overloaded($object);
	$object;
}

package main;

use Test::Most;
use PDL;
use Data::Perl qw(number);
use Number::Fraction;

# compile once to enable SvAMAGIC on new objects from each package
# RT #112708: Overload in runtime <https://rt.perl.org/Ticket/Display.html?id=112708>
# so either run these ahead of time or use v5.18
#
# see also:
# <https://metacpan.org/source/MooseX::Role::WithOverloading::Meta::Role::Application>
# <https://metacpan.org/source/MooseX::Role::WithOverloading::Meta::Role::Application::FixOverloadedRefs>
# <https://metacpan.org/source/ETHER/MooseX-Role-WithOverloading-0.13/WithOverloading.xs>
#OOverload->mangle( pdl(0), 'm' );
#OOverload->mangle( number(0), 'm' );

my $p = pdl q[4 2];
my $q = pdl q[2 3];

OOverload->mangle( $p, 'm' );
OOverload->mangle( $q, 's' );

is( "$p", "[4 2]~m", '$p is a PDL in metres');
is( "$q", "[2 3]~s", '$q is a PDL in seconds');

my $y = OOverload->mangle( pdl(q[2 2]) , 'm*s' );

is( "$y", "[2 2]~m*s", '$y is a PDL in m*s');

my $z = $p * $q;
is( "$z", '[8 6]~m*s', q|multiplying units of 'm' and 's' gives 'm*s'|);
diag "$p * $q = $z";

my $add_z_y = $z + $y;
is( "$add_z_y", '[10 8]~m*s', q|Two 'm*s' units can be added|);
diag "$z + $y = $add_z_y";


my $div_p_q = $p / $q;
is( "$div_p_q", '[2 0.66666667]~m/s', q|Dividing units of 'm' by 's' gives 'm/s'|);
diag "$p / $q = $div_p_q";

is( "@{[$p->sumover]}", "6~m", 'Summing keeps the same units');
is( "@{[$p->cumusumover]}", "[4 6]~m", 'Cumulative summing keeps the same units');


#say "--\nData::Perl::Number --- bug territory";
is( "@{[$p->avg]}", "3~m", "Average keeps the same units");

throws_ok { my $g = $z + $p; 1 } qr/Units not compatible/, q|Can not add 'm*s' to 'm'|;

my $half = OOverload->mangle(Number::Fraction->new(1, 2) , 'cup');
my $three = OOverload->mangle(Number::Fraction->new(3), '');

my $three_halves = $half * $three;

is( "$three_halves", '3/2~cup', 'multiplying fractions times dimensionless value');

done_testing;
