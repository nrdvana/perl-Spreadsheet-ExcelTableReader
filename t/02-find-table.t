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
		name => 'exact match',
		data => [ [qw( a b c d )] ],
		fields => [qw( a b c d )],
		cols => { a=>0, b=>1, c=>2, d=>3 }
	},
	{
		name => 'cols re-ordered',
		data => [ [qw( a b d c )] ],
		fields => [qw( a b c d )],
		cols => { a=>0, b=>1, c=>3, d=>2 },
	},
	{
		name => 'extra cols',
		data => [ [qw( x y z a b c e g d )] ],
		fields => [qw( a b c d )],
		cols => { a=>3, b=>4, c=>5, d=>8 },
	},
	{
		name => 'missing non-required col',
		data => [ [qw( b c d )] ],
		fields => [ { name => 'a', required => 0 }, 'b', 'c', 'd' ],
		cols => { b => 0, c => 1, d => 2 }
	},
	{
		name => 'duplicate column',
		data => [ [qw( a a b c d )] ],
		fields => [qw( a b c d )],
		cols => undef,
	},
	{
		name => 'ambiguous headers',
		data => [ [qw( ab ba )] ],
		fields => [
			{ name => 'a', header => qr/a/ },
		],
		cols => undef
	},
	{
		name => 'nearly ambiguous headers',
		data => [ [qw( foobar bar foo )] ],
		fields => [
			{ name => 'foo', header => qr/foo/ },
			{ name => 'foobar', header => qr/foobar/ },
			{ name => 'bar', header => qr/bar/ },
		],
		cols => { foo => 2, foobar => 0, bar => 1 },
	},
	{
		name => 'ambiguous header sudoku',
		data => [ [qw( abcfg afg acfg acdef abcdf ag a )] ],
		fields => [
			{ name => 'a', header => qr/a/ },
			{ name => 'b', header => qr/b/ },
			{ name => 'c', header => qr/c/ },
			{ name => 'd', header => qr/d/ },
			{ name => 'e', header => qr/e/ },
			{ name => 'f', header => qr/f/ },
			{ name => 'g', header => qr/g/ },
		],
		cols => { a => 6, b => 0, c => 2, d => 4, e => 3, f => 1, g => 5 },
	},
);

for (@tests) {
	my ($name, $data, $fields, $field_cols)= @{$_}{'name','data','fields','cols'};
	subtest $name => sub {
		my $sheet= TestSheet->new($data);
		my $tr= Spreadsheet::ExcelTableReader->new(fields => $fields, sheet => $sheet);
		if ($field_cols) {
			if (!$tr->find_table) {
				fail 'find table';
			} else {
				is_deeply( $tr->table_location->{field_col}, $field_cols, 'found correct field mapping' )
					or explain $tr->table_location->{field_col}
			}
		} else {
			ok(!$tr->find_table, 'should not find table' );
		}
	};
}

done_testing;
