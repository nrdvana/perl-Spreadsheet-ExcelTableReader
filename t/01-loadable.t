#! /usr/bin/env perl
use strict;
use warnings;
use Test::More;

use_ok( 'Spreadsheet::ExcelTableReader' ) or BAIL_OUT;

{
	package TestCell;
	sub new {
		my ($class, $value)= @_;
		bless \$value, $class;
	}
	sub value { ${ $_[0] } }
}
{
	package TestSheet;
	sub new {
		my ($class, $data)= @_;
		bless { data => $data }, $class;
	}
	sub name { 'test' }
	sub get_cell {
		my ($self, $row, $col)= @_;
		DummyCell->new($self->{data}[$row][$col]);
	}
}

my $sheet= TestSheet->new([
	[ 'foo', 'bar' ],
	[ 1, 2 ],
	[ 3, 4 ],
]);

my $tr= new_ok( 'Spreadsheet::ExcelTableReader', [
	fields => [ 'foo', 'bar' ],
	sheet => $sheet
]);

is( scalar($tr->field_list), 2, '2 fields' );
is( $tr->fields->[0]->name, 'foo', 'first field "foo"' );
like( 'Foo ', $tr->fields->[0]->header_pattern, 'foo header pattern' );

done_testing;
