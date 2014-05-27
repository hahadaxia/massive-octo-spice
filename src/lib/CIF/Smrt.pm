package CIF::Smrt;

use strict;
use warnings;

use Mouse;
use CIF qw/hash_create_random normalize_timestamp is_ip init_logging $Logger/;
require CIF::Client;
require CIF::ObservableFactory;
require CIF::RuleFactory;
require CIF::Smrt::HandlerFactory;

use Data::Dumper;
use Config::Simple;
use Carp::Assert;

use constant MAX_DATETIME => 999999999999999999;

has 'config'    => (
    is      => 'ro',
    isa     => 'HashRef',
);

has 'client_config' => (
    is      => 'ro',
    isa     => 'HashRef',
);

has 'client' => (
    is      => 'ro',
    isa     => 'CIF::Client',
    reader  => 'get_client',
);

has 'is_test'   => (
    is      => 'ro',
    isa     => 'Bool',
);

has 'other_attributes'  => (
    is      => 'ro',
    isa     => 'HashRef',
);

has 'handler'   => (
    is      => 'rw',
    reader  => 'get_handler',
    writer  => 'set_handler',
);

has 'rule'   => (
    is      => 'rw',
    writer  => 'set_rule',
    reader  => 'get_rule',
);

has 'test_mode' => (
    is      => 'ro',
    isa     => 'Bool',
    reader  => 'get_test_mode',
);

around BUILDARGS => sub {
    my $orig = shift;
    my $self = shift;
    my $args = shift;   

    if($args->{'config'}){
        die "config file doesn't exist: ".$args->{'config'} unless(-e $args->{'config'});
        $args->{'client_config'} = Config::Simple->new($args->{'config'})->get_block('client');
        $args->{'config'} = Config::Simple->new($args->{'config'})->get_block('smrt');
        $args = { %{$args->{'config'}},  %$args };
    }
    
    if($args->{'client_config'}){
        $args->{'client'} = CIF::Client->new($args->{'client_config'});   
    }
    
    init_logging({ level => 'ERROR'}) unless($Logger);
 
    return $self->$orig($args);
};

sub process {
    my $self = shift;
    my $args = shift;

    $self->set_rule(
        CIF::RuleFactory->new_plugin($args->{'rule'})
    );

    $Logger->info('starting at: '.
        DateTime->from_epoch(epoch => $self->get_rule->get_not_before())->datetime(),'Z'
    );
    
    $self->set_handler(
        CIF::Smrt::HandlerFactory->new_plugin({
            rule        => $self->get_rule(),
            test_mode   => $self->get_test_mode(),
        }),
    );
    
    $Logger->info('processing...');
    my $ret = $self->get_handler()->process($self->get_rule());
    return 0 unless($ret);

    my @array;
    $Logger->info('building events: '.($#{$ret} + 1));
    my $ts;

    ## TODO -- re-work me so with { data => $_ }, for some reason undef keeps popping up
    foreach (@$ret){
        $ts = $_->{'detecttime'} || $_->{'lasttime'} || $_->{'reporttime'} || MAX_DATETIME();
        $ts = normalize_timestamp($ts)->epoch();

        next unless($self->get_rule()->get_not_before() <= $ts );
        $_ = $self->get_rule()->process({ data => $_ });
        push(@array,$_);
    }
    return \@array;
}

sub ping_router {
    my $self = shift;
    my $args = shift;
    
    my $ret = $self->get_client->ping();
    return $ret;
}

sub DESTROY {
    my $self = shift;
    $self->get_client->get_broker()->shutdown();
}

__PACKAGE__->meta->make_immutable(inline_destructor => 0);

1;
