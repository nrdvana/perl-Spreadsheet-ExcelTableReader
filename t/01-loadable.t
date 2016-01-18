#! /usr/bin/env perl
use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";
use TestUtil;

use_ok( 'Spreadsheet::ExcelTableReader' ) or BAIL_OUT;

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
like( 'Foo ', $tr->fields->[0]->header_regex, 'foo header pattern' );

done_testing;
