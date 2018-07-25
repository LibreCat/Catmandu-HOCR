package Catmandu::Importer::HOCR;
use Catmandu::Sane;
use Catmandu::Util qw(is_natural);
use Moo;
use XML::LibXML;
use namespace::clean;

with "Catmandu::Importer";

sub _parse_ocr_attr {

    my ( $key, $value ) = @_;

    if ( $key eq "bbox" ) {

        my @coords = map { int($_) } split( " ", $value );
        return +{
            x1 => $coords[0], y1 => $coords[1],
            x2 => $coords[2], y2 => $coords[3]
        };

    }
    elsif ( $key eq "x_wconf" ) {

        return int($value);

    }

    $value;

}

sub _parse_ocr_attrs {

    my $title = $_[0];

    map {
        $_ =~ s/^\s+//o;
        $_ =~ s/\s+$//o;

        my $idx = index( $_, " " );
        my $key;
        my $val;

        if( $idx >= 0 ) {
            $key = substr( $_, 0, $idx );
            $val = substr( $_, $idx + 1 );
            $val = _parse_ocr_attr( $key, $val );
        }
        else {
            $key = $_;
            $val = undef;
        }

        $key => $val;
    } split( ";", $title );

}

sub _hocr_to_annotations {
    my ( $fh, %args ) = @_;

    my @annotations;

    #libxml requires binmode
    binmode $fh;
    my $dom = XML::LibXML->load_html(
        IO => $fh,
        recover => 1
    );

    my $page_nr = 0;

    for my $page ( $dom->findnodes('//*[contains(@class,"ocr_page")]') ) {

        $page_nr++;

        my $page_title = $page->findvalue('@title');

        my %page_attrs = _parse_ocr_attrs( $page_title );
        my $page_width = $page_attrs{bbox}->{x2} - $page_attrs{bbox}->{x1};
        my $page_height = $page_attrs{bbox}->{y2} - $page_attrs{bbox}->{y1};

        #between ocr_page and ocr_line can be ocr_block or ocr_par
        for my $line ( $page->findnodes( './/*[contains(@class,"ocr_line")]' ) ) {

            my $line_title = $line->findvalue('@title');
            my %line_attrs = _parse_ocr_attrs( $line_title );
            my $line_bbox = $line_attrs{bbox};
            my $line_x = $line_bbox->{x1};
            my $line_y = $line_bbox->{y1};
            my $line_width = $line_bbox->{x2} - $line_bbox->{x1};
            my $line_height = $line_bbox->{y2} - $line_bbox->{y1};

            my @words;

            #google supports ocrx_word, not ocr_word
            for my $word (
                $line->findnodes( './/*[contains(@class,"ocr_word")]' ),
                $line->findnodes( './/*[contains(@class,"ocrx_word")]' )
            ) {

                push @words, $word->textContent();

            }

            my $x = int($line_x);
            my $y = int($line_y);
            my $w = int($line_width);
            my $h = int($line_height);


            push @annotations,{
                text => join(' ',@words),
                x => $x,
                y => $y,
                w => $w,
                h => $h,
                page => $page_nr,
                page_w => $page_width,
                page_h => $page_height
            };
        }

    }

    \@annotations;

}
sub generator {

    my $self = $_[0];

    sub {
        state $annotations;

        unless ( defined( $annotations ) ) {
            $annotations = _hocr_to_annotations( $self->fh );
        }

        shift @$annotations;
    };

}

1;
