package Spreadsheet::ExcelTableReader::Field;
use Moo 2;

has name     => ( is => 'rw', required => 1 );
has header   => ( is => 'rw', required => 1 );
has required => ( is => 'rw', default => sub { 1 } );
has trim     => ( is => 'rw', default => sub { 1 } );
has blank    => ( is => 'rw' ); # default is undef
has validate => ( is => 'rw', isa => sub { $_[0]->can('check') }, required => 0 );

has header_pattern => ( is => 'lazy' );
sub _build_header_pattern {
	my $self= shift;
	my $h= $self->header;
	return $h if ref($h) eq 'Regexp';
	return $self->trim? qr/^\s*\Q$h\E\s*$/ : qr/^\Q$h\E$/;
}

1;
