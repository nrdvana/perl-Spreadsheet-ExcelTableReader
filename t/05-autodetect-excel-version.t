#! /usr/bin/env perl
use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";
use TestUtil;
use Log::Any::Adapter 'TAP';

use_ok( 'Spreadsheet::ExcelTableReader' ) or BAIL_OUT;

open my $fh, "<", "$FindBin::Bin/data/test.xls" or die "open: $!";
new_ok
	'Spreadsheet::ExcelTableReader',
	[ file => $fh, 	fields => [qw( a b c d )] ],
	'xls from GLOBref';

open my $fh2, "<", "$FindBin::Bin/data/test.xlsx" or die "open: $!";
new_ok
	'Spreadsheet::ExcelTableReader',
	[ file => $fh2, fields => [qw( a b c d )] ],
	'xlsx from GLOBref';

$fh= IO::File->new("$FindBin::Bin/data/test.xls", 'r') or die "open: $!";
new_ok
	'Spreadsheet::ExcelTableReader',
	[ file => $fh, fields => [qw( a b c d )] ],
	'xls from IO::File';

$fh2= IO::File->new("$FindBin::Bin/data/test.xlsx", 'r') or die "open: $!";
new_ok
	'Spreadsheet::ExcelTableReader',
	[ file => $fh2, fields => [qw( a b c d )] ],
	'xlsx from IO::File';

new_ok
	'Spreadsheet::ExcelTableReader',
	[ file => "$FindBin::Bin/data/test.xls", fields => [qw( a b c d )] ],
	'xls from filename';

new_ok
	'Spreadsheet::ExcelTableReader',
	[ file => "$FindBin::Bin/data/test.xlsx", fields => [qw( a b c d )] ],
	'xlsx from filename';

{
	package TestStringify;
	use overload '""' => sub { ${shift()} }
}

new_ok
	'Spreadsheet::ExcelTableReader',
	[ file => bless(\"$FindBin::Bin/data/test.xls",'TestStringify'), fields => [qw( a b c d )] ],
	'xls from filename stringify';

new_ok
	'Spreadsheet::ExcelTableReader',
	[ file => bless(\"$FindBin::Bin/data/test.xlsx",'TestStringify'), fields => [qw( a b c d )] ],
	'xlsx from filename stringify';

done_testing;
