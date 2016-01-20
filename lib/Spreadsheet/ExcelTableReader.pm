package Spreadsheet::ExcelTableReader;
use Moo 2;
use Spreadsheet::ParseExcel;
use Spreadsheet::ParseExcel::Utility 'int2col';
use Spreadsheet::XLSX;
use Log::Any '$log';
use Spreadsheet::ExcelTableReader::Field;
use Carp 'croak';
use IO::Handle;

our $VERSION= '0.000001_002';

# ABSTRACT: Module to extract a table from somewhere within an Excel spreadsheet

=head1 DESCRIPTION

Reading data from a spreadsheet isn't too hard thanks to modules like L<Spreadsheet::ParseExcel>
and L<Spreadsheet::XLSX>, and L<Data::Table::Excel>.  The problem comes from the users, when they
are exchanging files, adding rows or columns, or otherwise mucking around with the layout.

The purpose of this module is to help you find your data table somewhere within an excel file, and
clean up and/or validate the values as you extract them.
It uses the names (or regexes) of header columns to locate the header row, and then pulls the data
rows below that until the first blank row (or end of file).  The columns do not need to be in the
same order as you specified, and you have the option to ignore unknown columns, and the option to
proceed even if not all of your columns were found.

The default options are to make sure it found all your data columns, ignore extra columns, strip
off whitespace, and throw exceptions if it can't do those things.

=head1 SYNOPSIS

  my $tr= Spreadsheet::ExcelTableReader->new(
	file   => $filename_or_parser_instance,
	sheet  => $pattern_or_sheet_ref,  # optional. will search all sheets otherwise
	fields => [
		{ name => 'isbn', header => qr/isbn/i, isa => ISBN }
		'author',
		'title',
		{ name => 'publisher', header => qr/publish/i },
		...
    ],
  );
  
  my $data= $tr->hashes;
  # -or-
  $data= $tr->arrays;
  # -or-
  my $i= $tr->iterator(hash => 1);
  while (my $rec= $i->()) { ... }

=head1 ATTRIBUTES

=head2 C<file>

This is either a filename (which gets coerced into a parser instance) or a parser instance that you
created.  Currently supported parsers are L<Spreadsheet::ParseExcel> and L<Spreadsheet::XLSX>.

C<file> is not required if you supplied a parser's worksheet object as L</sheet>

=cut

has file => ( is => 'ro' );

=head2 C<sheet>

This is either a sheet name, a regex for matching a sheet name, or a parser's worksheet instance.
It is also optional; if you don't specify a sheet then this table reader will search all sheets
looking for your table columns.

=cut

has sheet => ( is => 'ro' );

# Arrayref of all sheets we can search
has _sheets => ( is => 'lazy' );

=head2 fields

Fields is an array of field specifications (L<Spreadsheet::ExcelTableReader::Field>) or a hashref
that constructs one, or just a simple string that we use to build a field with default values.

  # This
  fields => [ 'foo' ]
  
  # becomes this
  fields => [ Spreadsheet::ExcelTableReader::Field->new( 
    name     => 'foo',
    header   => qr/^\W*$foo\W*$/,
    required => 1,
    trim     => 1,
    blank    => undef
  ) ]

=head2 field_list

Convenient list accessor for L</fields>.  Not writeable.

=cut

has fields => ( is => 'ro', required => 1, coerce => \&_coerce_field_list );
sub field_list { @{ shift->fields } }

=head2 find_table_args

Supplies default arguments to L</find_table>.  These are ignored if you call C<find_table> directly.

=cut

has find_table_args => ( is => 'rw' );

has _table_location => ( is => 'rw', lazy_build => 1 );

sub _build__sheets {
	my $self= shift;
	
	# If we have ->sheet and it is a worksheet object, then no need to do anything else
	if ($self->sheet && ref($self->sheet) && ref($self->sheet)->can('get_cell')) {
		return [ $self->sheet ];
	}
	
	# Else we need to scan sheets from the excel file.  Make sure we have the file
	my $wbook= $self->_open_workbook($self->file);
	my @sheets= $wbook->worksheets;
	@sheets or croak "No worksheets in file?";
	if (defined $self->sheet) {
		if (ref($self->sheet) eq 'Regexp') {
			@sheets= grep { $_->get_name =~ $self->sheet } @sheets;
		} elsif (ref($self->sheet) eq 'CODE') {
			@sheets= grep { $self->sheet->($_) } @sheets;
		} elsif (!ref $self->sheet) {
			@sheets= grep { $_->get_name eq $self->sheet } @sheets;
		} else {
			croak "Unknown type of sheet specification: ".$self->sheet;
		}
	}
	@sheets or croak "No worksheets match the specification";
	
	return \@sheets;
}

sub _open_workbook {
	my ($self, $f)= @_;
	
	defined $f or croak "workbook file is undefined";
	
	my $wbook;
	if (ref($f) && ref($f)->can('worksheets')) {
		$wbook= $f;
	} else {
		my $type= "xlsx";
		
		# Probe the file to determine type
		if (ref($f) eq 'GLOB' or ref($f) && ref($f)->can('read')) {
			my $fpos= $f->tell;
			$fpos >= 0 or croak "File handle must be seekable";
			$f->read(my $buf, 4) == 4 or croak "read($f,4): $!";
			$f->seek($fpos, 0) or croak "failed to seek back to start of file";
			$type= 'xls' if $buf eq "\xD0\xCF\x11\xE0";
		}
		elsif (-e $f) {
			$f= "$f"; # force stringification
			open my $fh, '<', $f or croak "open($f): $!";
			read($fh, my $buf, 4) == 4 or croak "read($f,4): $!";
			$type= 'xls' if $buf eq "\xD0\xCF\x11\xE0";
		}
		else {
			$log->notice("Can't determine parser for '$f', guessing '$type'") if $log->is_notice;
		}
		
		if ($type eq 'xlsx') {
			# Spreadsheet::XLSX uses Archive::Zip which can *only* work on IO::Handle
			# instances, not plain globrefs. (seems like a bug, hm)
			if (ref($f) eq 'GLOB') {
				require IO::File;
				my $f_obj= IO::File->new;
				$f_obj->fdopen($f, 'r') or croak "Can't convert GLOBref to IO::File";
				$f= $f_obj;
			}
			$wbook= Spreadsheet::XLSX->new($f);
		} else {
			$wbook= Spreadsheet::ParseExcel->new->parse($f);
		}
		defined $wbook or croak "Can't parse file '".$self->file."'";
	}
	return $wbook;
}

sub _build__table_location {
	my $self= shift;
	my $args= $self->find_table_args;
	$self->find_table( !$args? () : (ref($args) eq 'ARRAY')? @$args : %$args )
		or croak "No match for table header in excel file";
	$self->{_table_location}; # find_table sets the value already, in a slight violation of this builder method.
}

sub _coerce_field_list {
	my ($list)= @_;
	defined $list and ref $list eq 'ARRAY' or croak "'fields' must be a non-empty arrayref";
	my @list= @$list; # clone it, to make sure we don't unexpectedly alter the caller's data
	for (@list) {
		if (!ref $_) {
			$_= Spreadsheet::ExcelTableReader::Field->new(
				name => $_,
				header => qr/^\s*\Q$_\E\s*$/i,
			);
		} elsif (ref $_ eq 'HASH') {
			my %args= %$_;
			# "isa" alias for the 'type' attribute
			$args{type}= delete $args{isa} if defined $args{isa} && !defined $args{type};
			# default header to field name with optional whitespace
			$args{header}= qr/^\s*\Q$args{name}\E\s*$/i unless defined $args{header};
			$_= Spreadsheet::ExcelTableReader::Field->new( %args )
		} else {
			croak "Can't coerce '$_' to a Field object"
		}
	}
	return \@list;
}

=head1 METHODS

=head2 new

Standard Moo constructor, accepting attributes as hash or hashref.
Dies if it doesn't have any sheets to work with.  (i.e. it tries to open the file if necessary, and
sees if any sheets match your C<sheet> specification)

=cut

sub BUILD {
	my $self= shift;
	# Any errors getting the list of searchable worksheets should happen now, during construction time
	$self->_sheets;
}

=head2 find_table

  $tr->find_table( %params )

Perform the search for the header row of the table.  After this is called, the rest of the
data-reading methods will pull from the located region of the spreadsheet.

Returns true if it located the header, or false otherwise.

=cut

sub _cell_name {
	my ($row, $col)= @_;
	return int2col($col).($row+1);
}

sub find_table {
	my $self= shift;
	
	my $location;
	my @sheets= @{$self->_sheets};
	my @fields= $self->field_list;
	my $num_required_fields= grep { $_->required } @fields;
	
	# Algorithm is O(N^4) in worst case, but the regex should make it more like O(N^2) in most
	# real world cases.  The worst case would be if every row of every sheet of the workbook almost
	# matched the header row (which could happen with extremely lax field header patterns) 
	my $header_regex= qr/(?:@{[ join('|', map { $_->header_regex } @fields) ]})/ms;

	# Scan top-down across all sheets at once, since headers are probably at the top of the document.
	my $row= 0;
	my $in_range= 1; # flag turns false if we pass the bottom of all sheets
	row_loop: while ($in_range) {
		$in_range= 0;
		for my $sheet (@sheets) {
			$log->trace("row $row sheet $sheet") if $log->is_trace;
			my %field_found;
			my ($rmin, $rmax)= $sheet->row_range();
			my ($cmin, $cmax)= $sheet->col_range();
			next unless $row >= $rmin && $row <= $rmax;
			$in_range++;
			my @row_vals= map { my $c= $sheet->get_cell($row, $_); $c? $c->value : '' } 0..$cmax;
			my $match_count= grep { $_ =~ $header_regex } @row_vals;
			$log->trace("str=@row_vals, regex=$header_regex, match_count=$match_count");
			if ($match_count >= $num_required_fields) {
				my $field_col= $self->_resolve_field_columns($sheet, $row, \@row_vals);
				if ($field_col) {
					$location= {
						sheet => $sheet,
						header_row => $row,
						min_row => $row+1,
						field_col => $field_col,
					};
					last row_loop;
				}
			}
		}
		++$row;
	}
	
	return '' unless defined $location;
	
	# Calculate a few more fields for location
	my @cols_used= sort { $a <=> $b } values %{ $location->{field_col} };
	$location->{min_col}= $cols_used[0];
	$location->{max_col}= $cols_used[-1];
	
	# Maybe should look for the last row containing data for our columns, but that seems expensive...
	$location->{max_row}= ($location->{sheet}->row_range())[1];
	
	$location->{start_cell}= _cell_name($location->{min_row}, $location->{min_col});
	$location->{end_cell}=   _cell_name($location->{min_col}, $location->{max_col});
	$self->_table_location($location);
	
	return 1;
}

sub _resolve_field_columns {
	my ($self, $sheet, $row, $row_vals)= @_;
	my %col_map;
	my %field_found;
	my $fields= $self->fields;
	
	# Try each cell to see if it matches each field's header
	for my $col (0..$#$row_vals) {
		my $v= $row_vals->[$col];
		next unless defined $v and length $v;
		for my $field (@$fields) {
			push @{ $field_found{$field->name} }, $col
				if $v =~ $field->header_regex;
		}
	}
	
	# Is there one and only one mapping of fields to columns?
	my $ambiguous= 0;
	my @todo= @$fields;
	while (@todo) {
		my $field= shift @todo;
		next unless defined $field_found{$field->name};
		my $possible= $field_found{$field->name};
		my @available= grep { !defined $col_map{$_} } @$possible;
		$log->trace("ambiguous=$ambiguous : field ".$field->name." could be ".join(',', map { _cell_name($row,$_) } @$possible)
			." and ".join(',', map { _cell_name($row,$_) } @available)." are available");
		if (!@available) {
			# It is possible that two fields claim the same columns and one is required
			if ($field->required) {
				my $col= $possible->[0];
				$log->debug("Field ".$field->name." and ".$col_map{$col}." would both claim "._cell_name($row, $col))
					if $log->is_debug;
				return;
			}
		}
		elsif (@available > 1) {
			# It is possible for a field to match more than one column.
			# If so, we send it to the back of the list in case another more specific
			# column claims one of the options.
			if (++$ambiguous > @todo) {
				$log->debug("Can't decide between ".join(', ', map { _cell_name($row,$_) } @available)." for field ".$field->name)
					if $log->is_debug;
				return;
			}
			push @todo, $field;
		}
		else {
			$col_map{$available[0]}= $field->name;
			$ambiguous= 0; # made progress, start counting over again
		}
	}
	# Success!  convert the col map to an array of col-index-per-field
	$log->debug("Found headers at ".join(' ', map { _cell_name($row,$_) } sort keys %col_map))
		if $log->is_debug;
	return { reverse %col_map };
}

=head2 table_location

Returns information about the location of the table after a successful find_table.  Returns undef
if find_table has not yet run.

  {
    header     => \@values,    # The literal header values we found
    start_cell => $cell_addr,  # The Excel cell address of the first data row, first column
    end_cell   => $cel_addr,   # The Excel cell address of the last data row, last column
  }

=cut

sub table_location {
	my ($self)= @_;
	return undef unless defined $self->{_table_location};
	# Deep-clone the location
	my %loc= %{ $self->_table_location };
	$loc{field_col}= { %{ $loc{field_col} } };
	return \%loc;
}

=head2 record_count

Returns the number of rows in the table, by a simple difference of Excel cell addresses.
You might get a smaller number of rows back if you configure the iterator to skip or stop at empty
rows.

=cut

sub record_count {
	my $self= shift;
	return 0 unless defined $self->_table_location;
	return $self->_table_location->{max_row} - $self->_table_location->{min_row} + 1;
}

=head2 records

  my $records= $tr->records( %options );

Returns an arrayref of records, each as a hashref (unless arrays are requested in %options).

=cut

sub records {
	my ($self, %opts)= @_;
	my $i= $self->iterator(%opts);
	my @records;
	while (my $r= $i->()) { push @records, $r; }
	return \@records;
}

=head2 record_arrays

Returns an arrayref of arrayrefs.  Shortcut for C<< $tr->records(as => 'array') >>.

=cut

sub record_arrays { shift->records(as => 'array', @_) }

=head2 iterator

  my $i= $tr->iterator(hash => 1);
  while ($rec= $i->()) {
    ...
  }

or if you want to ignore invalid data:

  my $i= $tr->iterator(on_error => '');
  while (1) {
    my $rec= $i->();
    last unless defined $rec;
    if (! ref $rec) { warn "Error on row ".$i->row.", but continuing\n" }
    else {
      ...
    }
  }

Returns a record iterator.  The iterator is a coderef which returns the next record each time you
call it.  The iterator is also blessed, so you can call methods on it!  Isn't that cool?

=cut

our %_Iterators;

sub iterator {
	my ($self, %opts)= @_;
	my ($as, $blank_row, $on_error)= delete @opts{'as','blank_row','on_error'};
	croak "Unknown option(s) to iterator: ".join(', ', keys %opts)
		if keys %opts;
	
	$as= 'hash' unless defined $as;
	my $hash= ($as eq 'hash');
	
	$blank_row= 'end' unless defined $blank_row;
	my $skip_blank_row= ($blank_row eq 'skip');
	my $end_blank_row=  ($blank_row eq 'end');
	
	my $sheet=     $self->_table_location->{sheet};
	my $min_row=   $self->_table_location->{min_row};
	my $row=       $min_row - 1;
	my $col;
	my $min_col=   $self->_table_location->{min_col};
	my $remaining= $self->_table_location->{max_row} - $self->_table_location->{min_row} + 1;
	my $is_blank_row;
	my %field_col= %{ $self->_table_location->{field_col} };
	my (@result_keys, @field_extractors, @validations);
	for my $field ($self->field_list) {
		my $blank= $field->blank;
		my $src_col= $field_col{$field->name};
		
		# Don't need an extractor for fields not found in the table if result type is hash,
		# but if result type is array we need to pad with a null value
		if (!defined $src_col) {
			$hash or push @field_extractors, sub { undef; };
			next;
		}
		
		push @result_keys, $field->name if $hash;
		
		# If trimming, use a different implementation than if not, for a little efficiency
		push @field_extractors, $field->trim?
			sub {
				my $v= $sheet->get_cell($row, $src_col);
				return $blank unless defined $v;
				$v= $v->value;
				$v =~ s/^\s*(.*?)\s*$/$1/;
				return $blank unless length $v;
				$is_blank_row= 0;
				$v;
			}
		:
			sub {
				my $v= $sheet->get_cell($row, $src_col);
				defined $v && length($v= $v->value)
					or return $blank;
				$is_blank_row= 0;
				$v;
			};
		
		if (defined (my $type= $field->type)) {
			# This sub will access the values array at the same position as the current field_extractor
			my $idx= $#field_extractors;
			push @validations, sub {
				return if $type->check($_[0][$idx]);
				$col= $src_col; # so the iterator->col reports the column of the error
				croak "Not a ".$type->name." at cell "._cell_name($row, $col);
			};
		}
	}
	
	# Closure over everything, for very fast access
	my $sub= sub {
		$log->trace("iterator: remaining=$remaining row=$row sheet=$sheet");
		again:
		return unless $remaining > 0;
		++$row;
		$col= $min_col;
		--$remaining;
		$is_blank_row= 1; # This var is closured, and gets set to 0 by the next line
		my @values= map { $_->() } @field_extractors;
		goto again if $skip_blank_row && $is_blank_row;
		if ($end_blank_row && $is_blank_row) {
			$remaining= 0;
			return;
		}
		$_->(\@values) for @validations; # This can die.  It can also be an empty list.
		return $hash? do { my %r; @r{@result_keys}= @values; \%r } : \@values;
	};
	
	# Blessed coderef, so we can call methods on it
	bless $sub, 'Spreadsheet::ExcelTableReader::Iterator';
	
	# Store references to all the closered variables so the methods can access them
	$_Iterators{$sub}= {
		r_sheet => \$sheet,
		r_row => \$row,
		r_col => \$col,
		r_remaining => \$remaining,
		min_row => $self->_table_location->{min_row},
		max_row => $self->_table_location->{max_row},
	};
	
	return $sub;
}

package Spreadsheet::ExcelTableReader::Iterator;

sub DESTROY   { delete $_Iterators{$_[0]}; }
sub sheet     { ${ $_Iterators{$_[0]}{r_sheet} } }
sub col       { ${ $_Iterators{$_[0]}{r_col} } }
sub row       { ${ $_Iterators{$_[0]}{r_row} } }
sub remaining { ${ $_Iterators{$_[0]}{r_remaining} } }

sub rewind {
	my $self= $_Iterators{$_[0]};
	${$self->{r_row}}= $self->{min_row} - 1;
	${$self->{r_remaining}}= $self->{max_row} - $self->{min_row} + 1;
	return 1;
}

1;

