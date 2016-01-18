#! /usr/bin/env perl
use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";
use TestUtil;
use Log::Any::Adapter 'TAP';

use_ok( 'Spreadsheet::ExcelTableReader' ) or BAIL_OUT;

my @tests= (
	{
		name => 'basic data table',
		sheet => undef,
		fields => [qw( A B C D )],
		values => [
			[qw( 1 2 3 xyz )],
			[qw( 1 2 03 abc )],
			[ 1, 2, '003', 'xyz' ],
		],
	},
	{
		name => 'basic data table, no trim',
		sheet => undef,
		fields => [ map { ; { name => $_, trim => 0 } } qw( A B C D )],
		values => [
			[ 1, 2, 3, 'xyz' ],
			[ 1, 2, '03  ', 'abc' ],
			[ 1, 2, ' 003', 'xyz  ' ],
		],
	},
);

for (@tests) {
	my ($name, $fields, $values)= @{$_}{'name','fields','values'};
	for my $type (qw( xls xlsx )) {
		subtest "$name - $type" => sub {
			my $tr= Spreadsheet::ExcelTableReader->new(
				file => "$FindBin::Bin/data/test.$type",
				fields => $fields,
			);
			if ($values) {
				if (!$tr->find_table) {
					fail 'find table';
				} else {
					my $rec= $tr->record_arrays;
					is_deeply( $rec, $values, 'extracted values' )
						or explain $rec;
				}
			} else {
				ok(!$tr->find_table, 'should not find table' );
			}
		};
	}
}

done_testing;
