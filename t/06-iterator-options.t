#! /usr/bin/env perl
use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";
use TestUtil;
use Log::Any::Adapter 'TAP';

use_ok( 'Spreadsheet::ExcelTableReader' ) or BAIL_OUT;

my $tr= Spreadsheet::ExcelTableReader->new(
	file => "$FindBin::Bin/data/test.xls",
	fields => [ 'name', 'first', 'last' ],
);

ok( $tr->find_table, 'found table' ) or die;

is_deeply(
	$tr->records(as => 'array'),
	[
		[ 'Testing',   'qwer', 'tyui' ],
		[ 'Testing 2', '1234', '5678' ],
		[ 'Testing 3', 'asdf', 'ghjk' ],
		[ 'Testing 4', 'zxcv', 'bnm,' ],
	],
	'as_array'
);

is_deeply(
	$tr->records,
	[
		{ name => 'Testing',   first => 'qwer', last => 'tyui' },
		{ name => 'Testing 2', first => '1234', last => '5678' },
		{ name => 'Testing 3', first => 'asdf', last => 'ghjk' },
		{ name => 'Testing 4', first => 'zxcv', last => 'bnm,' },
	],
	'as_hash'
);

is_deeply(
	$tr->records(blank_row => 'skip'),
	[
		{ name => 'Testing',   first => 'qwer', last => 'tyui' },
		{ name => 'Testing 2', first => '1234', last => '5678' },
		{ name => 'Testing 3', first => 'asdf', last => 'ghjk' },
		{ name => 'Testing 4', first => 'zxcv', last => 'bnm,' },
		{ name => 'Testing 5', first => 'wert', last => 'yuio' },
		{ name => 'Testing 6', first => 'sdfg', last => 'hjkl' },
		{ name => 'Testing 7', first => 'xcvb', last => 'nm,.' },
	],
	'skip blank lines'
);

{
	# Don't want to make this module depend on Type::Tiny, so just duck-type with this mockup
	package IsWord;
	sub check { $_[1] =~ /^[a-z]+$/ };
}

$tr= Spreadsheet::ExcelTableReader->new(
	file => "$FindBin::Bin/data/test.xls",
	fields => [
		'name',
		{ name => 'first', type => 'IsWord' },
		'last'
	],
);

$tr->find_table or die;

my $recs= $tr->records(on_error => sub { 'skip' });
is_deeply(
	$recs,
	[
		{ name => 'Testing',   first => 'qwer', last => 'tyui' },
		{ name => 'Testing 3', first => 'asdf', last => 'ghjk' },
		{ name => 'Testing 4', first => 'zxcv', last => 'bnm,' },
	],
	'skip error lines'
) or diag explain $recs;

$recs= $tr->records(on_error => sub { 'end' });
is_deeply(
	$recs,
	[
		{ name => 'Testing',   first => 'qwer', last => 'tyui' },
	],
	'end at first error'
) or diag explain $recs;

$recs= $tr->records(blank_row => 'skip', on_error => sub { $_[0]{errors}= 1; 'use' });
is_deeply(
	$recs,
	[
		{ name => 'Testing',   first => 'qwer', last => 'tyui' },
		{ name => 'Testing 2', first => '1234', last => '5678', errors => 1 },
		{ name => 'Testing 3', first => 'asdf', last => 'ghjk' },
		{ name => 'Testing 4', first => 'zxcv', last => 'bnm,' },
		{ name => 'Testing 5', first => 'wert', last => 'yuio' },
		{ name => 'Testing 6', first => 'sdfg', last => 'hjkl' },
		{ name => 'Testing 7', first => 'xcvb', last => 'nm,.' },
	],
	'munge record on error'
) or diag explain $recs;


done_testing;
