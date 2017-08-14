package MT::Plugin::SystemCFAsset;
use strict;
use warnings;
use utf8;

use base qw( MT::Plugin );

my $plugin = __PACKAGE__->new(
    {   name    => 'SystemCFAsset',
        version => 0.04,

        description =>
            '<__trans phrase="You can create and use asset-relative custom fields in system scope.">',
        plugin_link =>
            'https://github.com/masiuchi/mt-plugin-system-cf-asset',

        author_name => 'masiuchi',
        author_link => 'https://github.com/masiuchi',

        registry => {
            callbacks => {
                post_init => \&_overwrite_registry,
                init_app  => \&_overwrite_methods,
            },

            applications => {
                cms => {
                    callbacks => {
                        'template_param.asset_list' => \&_delete_upload_mode,
                    },
                },
            },

            l10n_lexicon => {
                ja => {
                    'You can create and use asset-relative custom fields in system scope.'
                        => 'システムスコープにおけるアイテムのカスタムフィールドを作成可能にします。',
                },
            },
        },
    }
);
MT->add_plugin($plugin);

sub _overwrite_registry {
    my $types = MT->registry('customfield_types') or return;

    require MT::Asset;
    my $asset_types = MT::Asset->class_labels;
    my @asset_types = sort { $asset_types->{$a} cmp $asset_types->{$b} }
        keys %$asset_types;

    for my $type (@asset_types) {
        if ( $type =~ /^asset\.(\w+)/ ) {
            $type = $1;
        }

        delete $types->{$type}{context};

        my $original = $types->{$type}{field_html_params};
        $types->{$type}{field_html_params} = sub {
            $original->(@_);
            $_[2]->{blog_id} = MT->app->blog->id if MT->app->blog;
        };
    }
}

sub _delete_upload_mode {
    my ( $cb, $app, $param, $tmpl ) = @_;
    return unless $app->request('fake_upload_mode');
    delete $param->{upload_mode};
}

use MT::CMS::Asset;
my $orig_dialog_list_asset = \&MT::CMS::Asset::dialog_list_asset;
my $orig_upload_file       = \&MT::CMS::Asset::upload_file;
my $orig_complete_insert   = \&MT::CMS::Asset::complete_insert;

use MT::App;
my $orig_listing = \&MT::App::listing;

sub _overwrite_methods {
    no warnings 'redefine';
    *MT::CMS::Asset::dialog_list_asset = \&_new_dialog_list_asset;
    *MT::CMS::Asset::upload_file       = \&_new_upload_file;
    *MT::CMS::Asset::complete_insert   = \&_new_complete_insert;
}

sub _new_dialog_list_asset {
    my $app = shift;

    my $blog_id      = $app->param('blog_id')     || 0;
    my $mode_userpic = $app->param('upload_mode') || '';
    my $edit_field   = $app->param('edit_field')  || '';

    unless ( !$blog_id
        && $mode_userpic ne 'upload_userpic'
        && $edit_field =~ m/^customfield_.*$/ )
    {
        return $orig_dialog_list_asset->( $app, @_ );
    }

    # Set system permissions.
    local $app->{perms} = $app->user->permissions($blog_id);

    # Fake upload_mode temporarily.
    my $query      = $app->param;
    my @parameters = @{ $query->{'.parameters'} };
    local @{ $query->{'.parameters'} } = ( @parameters, 'upload_mode' );
    local $query->{param}{upload_mode} = ['upload_userpic'];

    # Set a flag for resetting fake.
    $app->request( 'fake_upload_mode', 1 );

    # Exclude userpics.
    local *MT::App::listing = \&_new_listing;

    return $orig_dialog_list_asset->( $app, @_ );
}

sub _new_listing {
    my ( $app, $opt ) = @_;

    if ( !$opt->{params}{is_image} ) {
        return $orig_listing->(@_);
    }

    require MT::Tag;
    my $tag = MT::Tag->load( { name => '@userpic' },
        { binary => { name => 1 } } );
    if ($tag) {
        require MT::ObjectTag;
        my @object_tags = MT::ObjectTag->load(
            {   tag_id            => $tag->id,
                object_datasource => MT::Asset->datasource
            }
        );
        if (@object_tags) {
            my @asset_ids = map { $_->object_id } @object_tags;
            $opt->{terms}{id} = { not => \@asset_ids };
        }
    }

    return $orig_listing->(@_);
}

sub _new_upload_file {
    my $app = shift;

    my $blog_id    = $app->param('blog_id')    || 0;
    my $edit_field = $app->param('edit_field') || '';

    unless ( !$blog_id && $edit_field =~ m/^customfield_.*$/ ) {
        return $orig_upload_file->( $app, @_ );
    }

    # Set system permissions.
    local $app->{perms} = $app->user->permissions($blog_id);

    return $orig_upload_file->( $app, @_ );
}

sub _new_complete_insert {
    my $app = shift;

    my $blog_id    = $app->param('blog_id')    || 0;
    my $edit_field = $app->param('edit_field') || '';

    unless ( !$blog_id && $edit_field =~ m/^customfield_.*$/ ) {
        return $orig_complete_insert->( $app, @_ );
    }

    # Set system permissions.
    local $app->{perms} = $app->user->permissions($blog_id);

    # Set dummy website for passing check.
    my $dummy = $app->model('website')->load;
    require MT::Asset;
    local *MT::Asset::blog = sub {$dummy};

    return $orig_complete_insert->( $app, @_ );
}

1;
