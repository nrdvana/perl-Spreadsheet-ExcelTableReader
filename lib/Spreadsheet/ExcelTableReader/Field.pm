package Spreadsheet::ExcelTableReader::Field;
use Moo 2;

# ABSTRACT: Field description for Spreadsheet::ExcelTableReader

=head1 DESCRIPTION

This class describes aspects of one of the fields you want to find in your spreadsheet.

=head1 ATTRIBUTES

=head2 name

Required.  Used for the hashref key if you pull records as hashes, and used in diagnostic messages.

=head2 header

A string or regex describing the column header you want to find in the spreadsheet.  Defaults to a
case-insensitive match of C<name> with allowed prefix/suffix of non-word (C<\W>) garbage.  If you
specify a regex, it is used directly.  If you specify a string, the regex will match exactly that
string (case-sensitive) but also C<trim> depending on that attribute.

=head2 required

Whether or not this field must be found in order to read a table.  Defaults to true.

=head2 trim

Whether or not to remove prefix/suffix whitespace from each value of the field.  defaults to true.

=head2 blank

The value to extract when the spreadsheet cell is empty.  (where "empty" depends on the value of
C<trim>).  Default is undef.  Other common value would be C<"">.

=head2 type

A L<Type::Tiny> type (or any object or class with a C<check> method) which will validate each value
pulled from a cell for this field.  Optional.  No default.

=cut

has name     => ( is => 'ro', required => 1 );
has header   => ( is => 'ro', required => 1 );
has required => ( is => 'ro', default => sub { 1 } );
has trim     => ( is => 'ro', default => sub { 1 } );
has blank    => ( is => 'ro' ); # default is undef
has type     => ( is => 'ro', isa => sub { $_[0]->can('check') }, required => 0 );

=head2 header_regex

C<header>, coerced to a regex according to the description in L</header>

=cut

has header_regex => ( is => 'lazy' );
sub _build_header_regex {
	my $self= shift;
	my $h= $self->header;
	return $h if ref($h) eq 'Regexp';
	return $self->trim? qr/^\s*\Q$h\E\s*$/ : qr/^\Q$h\E$/;
}

1;
