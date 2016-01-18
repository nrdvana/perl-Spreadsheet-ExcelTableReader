package TestUtil;
use strict;
use warnings;

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
		my $max_col= 0;
		($#$_ > $max_col) && ($max_col= $#$_) for @$data;
		bless { data => $data, max_col => $max_col }, $class;
	}
	sub col_range { return 0, $_[0]{max_col} }
	sub row_range { return 0, $#{$_[0]{data}} }
	sub name { 'test' }
	sub get_cell {
		my ($self, $row, $col)= @_;
		TestCell->new($self->{data}[$row][$col]);
	}
}

1;
