package OpenXPKI::Connector::DataPool;

use Moose;
extends 'Connector';

use English;
use DateTime;
use Data::Dumper;
use OpenXPKI::DateTime;
use OpenXPKI::Server::Context qw( CTX );


has key => (
    is  => 'ro',
    isa => 'Str',
);

has value => (
    is  => 'rw',
    isa => 'HashRef|Str',
);

has encrypt => (
    is => 'ro',
    isa => 'Bool',
    default => 0,
);


# FIXME - the get* methods are untested
sub get {

    my $self = shift;
    my $args = shift;
    my $params = shift;

    my @args = $self->_build_path( $args );

    my $ttarg = {
        ARGS => \@args
    };

    if (defined $params->{extra}) {
        $ttarg->{EXTRA} = $params->{extra};
    }

    $self->log()->trace('Template args ' . Dumper $ttarg ) if $self->log->is_trace;

    # Process the key using template if necessary
    my $key = $self->key();
    my $template = Template->new({});
    my $parsed_key;
    $template->process(\$key, $ttarg, \$parsed_key) || die "Error processing argument template.";

    my $result = CTX('api2')->get_data_pool_entry(
        'namespace' => $self->LOCATION(),
        'key' => $parsed_key,
    );

    if (!defined $result) {
        return $self->_node_not_exists();
    }

    return $result->{value};

}

sub get_list {

    my $self = shift;

    my $val = $self->get( @_ );

    if (!defined $val) {
        return;
    }

    my $res;
    eval {
        $res = OpenXPKI::Serialization::Simple->new()->deserialize( $val );
    };
    if (!defined $res || ref $res ne 'ARRAY') {
        die "requested value is not a list";
    }
    return @{$res};

}

sub get_hash {

    my $self = shift;

    my $val = $self->get( @_ );

    if (!defined $val) {
        return;
    }

    my $res;
    eval {
        $res = OpenXPKI::Serialization::Simple->new()->deserialize( $val );
    };
    if (!defined $res || ref $res ne 'HASH') {
        die "requested value is not a hash";
    }
    return $res;

}

sub get_meta {

    my $self = shift;

    my $val = $self->get( @_ );

    if (!defined $val) {
        return;
    }

    my $res;
    eval {
        $res = OpenXPKI::Serialization::Simple->new()->deserialize( $val );
    };
    if (!defined $res || ref $res eq '') {
        # Treat it as a scalar
        return {TYPE  => "scalar" };
    } elsif (ref $res eq 'ARRAY') {
        return {TYPE  => "list" };
    } elsif (ref $res eq 'HASH') {
        return {TYPE  => "hash" };
    }

    die "Unknown data structure";

}

sub set {

    my $self = shift;
    my $args = shift;
    my $value = shift;
    my $params = shift;

    my @args = $self->_build_path( $args );

    $self->log()->trace('Set called on ' . Dumper \@args ) if $self->log->is_trace;

    my $template = Template->new({});

    my $ttarg = {
        ARGS => \@args
    };

    if (defined $params->{extra}) {
        $ttarg->{EXTRA} = $params->{extra};
    }

    $self->log()->trace('Template args ' . Dumper $ttarg ) if $self->log->is_trace;
    # Process the key using template
    my $key = $self->key();
    my $parsed_key;
    $template->process(\$key, $ttarg, \$parsed_key) || die "Error processing argument template.";

    # Parse values
    my $dpval;
    my $valmap = $self->value();

    if (ref $valmap eq '') {
        $template->process(\$valmap, $ttarg, \$dpval);
    } else {
        foreach my $key (keys %{$valmap}) {
            my $val;
            $template->process(\$valmap->{$key}, $ttarg, \$val);
            $dpval->{$key} = $val if ($val);
        }
        $dpval = OpenXPKI::Serialization::Simple->new()->serialize( $dpval );
    }

    $self->log()->debug('Namespace key is' . $parsed_key . ', values ' . $dpval);

    CTX('api2')->set_data_pool_entry(
        'namespace' => $self->LOCATION(),
        'key' => $parsed_key,
        'value' => $dpval,
        'encrypt' => $self->encrypt(),
        'force' => 1
    );

    return 1;

}

__PACKAGE__->meta->make_immutable;

__END__

=head1 NAME

OpenXPKI::Connector::DataPool;

=head1 DESCRIPTION

Connector to interact with the datapool, the LOCATION defindes the namespace.
If you pass additional parameters (e.g. from workflow context) by setting
{ extra => ... } in the control parameter, those values are available in the
EXTRA hash inside all template operations.

=head2 Configuration

=over

=item key

Scalar, evaluated using template toolkit.

=item value

scalar value or key/value list, values are evaluated using template toolkit.
If value is a hash, OpenXPKI::Serialization::Simple is used to store the value.


=back

