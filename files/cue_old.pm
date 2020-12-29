# Copyright (C) 2006-2007 Quentin Sculo <squentin@free.fr>
#
# This file is part of Gmusicbrowser.
# Gmusicbrowser is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3, as
# published by the Free Software Foundation

=gmbplugin CUE
Cue
Cue plugin
Display cue sheet of selected song
=cut

package GMB::Plugin::CUE;
use strict;
use warnings;

use Gtk2::Pango;
use base 'Gtk2::VBox';
use constant
{	title => _"Cue sheet",
};

sub Start
{	GMB::Context::AddPackage(__PACKAGE__,'Cue');
}
sub Stop
{	GMB::Context::RemovePackage('Cue');
}

sub prefbox
{	my $vbox=Gtk2::VBox->new(::FALSE, 2);
	my $Bopen=Gtk2::Button->new('open context window');
	$Bopen->signal_connect(clicked => sub { ::ContextWindow; });
	$vbox->pack_start($Bopen,::FALSE,::FALSE,1);
	return $vbox;
}

sub new
{	my $class=$_[0];
	my $self = bless Gtk2::VBox->new, $class;
	my $store=Gtk2::ListStore->new( ('Glib::String')x4, 'Glib::Int' );
	$self->{treeview}=my $treeview=Gtk2::TreeView->new($store);
	my $n=0;
	for (qw/track title performer index/)
	{	$treeview->append_column( Gtk2::TreeViewColumn->new_with_attributes
		 ( $_,Gtk2::CellRendererText->new,'text',$n++,'weight',4) );
	}
	$treeview->signal_connect (row_activated => sub {$self->SkipTo($_[1])});

	my $sw=Gtk2::ScrolledWindow->new(undef, undef);
	$sw->set_shadow_type('etched-in');
	$sw->set_policy('automatic', 'automatic');
	$sw->add($treeview);
	$self->add($sw);
	$self->show_all;
	$sw->hide;
	::Watch($self,'Time',\&TimeChanged);
	return $self;
}

sub SkipTo
{	my ($self,$treepath)=@_;
	my $store=$self->{treeview}->get_model;
	my $iter=$store->get_iter($treepath);
	my $track=$store->get_value($iter,0);
	my $sec=$self->{tracks}[$track]{'index'}/75;
	if (defined $::SongID && $::SongID==$self->{ID}) { ::SkipTo($sec) }
	else	{ ::Stop(); ::Select(song=>$self->{ID}); ::Play($sec) }
}

sub TimeChanged
{	my $self=$_[0];
	return unless defined $self->{ID};
	my $tracks=$self->{tracks};
	return unless @$tracks;
	my $index;
	if (!defined $::PlayTime || $self->{ID}!=$::SongID)
	{	return unless $self->{boldtrack};
		$index=-1;
	}
	else { $index=$::PlayTime*75+74 }
	my $store=$self->{treeview}->get_model;
	my $n=0;
	for my $track (1..$#$tracks)
	{	my $h=$tracks->[$track];
		next unless $h;
		$n=$track if $index >= $tracks->[$track]{'index'};
	}
	return if $n==$self->{boldtrack};
	$self->{boldtrack}=$n;
	my $iter=$store->get_iter_first;
	while ($iter)
	{	my $track=$store->get_value($iter,0);
		my $bold= $track==$n ? PANGO_WEIGHT_BOLD : PANGO_WEIGHT_NORMAL;
		$store->set($iter,4,$bold);
		$iter=$store->iter_next($iter);
	}
}

sub SongChanged
{	my ($self,$ID)=@_;
	return unless defined $ID;
	return if defined $self->{ID} && $ID==$self->{ID};

	$self->{ID}=$ID;
	my @tracks; $self->{tracks}=\@tracks;
	$self->{boldtrack}=0;
	my $treeview=$self->{treeview};
	my $store=$treeview->get_model;
	$store->clear;

	my $ref=$::Songs[$ID];
	my $file=$ref->[::SONG_PATH].::SLASH.$ref->[::SONG_FILE];
	$file=~s/\.[^.]*$/.cue/;
	{	last if -r $file;
		$file=~s/cue$/CUE/;
		last if -r $file;
		$treeview->parent->hide;
		return;
	}
	$treeview->parent->show;
	open my$fh,'<:utf8',$file;
	my $found; my $track;
	$file=$ref->[::SONG_UFILE];
	for (<$fh>)
	{	if (m/^FILE "\Q$file\E"/) {$found=1;next}
		next unless $found;
		warn $_ if $::debug;
		last if m/^FILE/;
		if (m/^\s*TRACK (\d+) AUDIO/) {$track=$1}
		elsif ($track and m/^\s*TITLE "([^"]*)"/) {$tracks[$track]{title}=$1}
		elsif ($track and m/^\s*PERFORMER "([^"]*)"/) {$tracks[$track]{performer}=$1}
		elsif (m/^\s*INDEX 01 (\d\d):(\d\d):(\d\d)/) {$tracks[$track]{'index'}=(($1*60)+$2)*75+$3}
	}
	close $fh;
	for my $track (1..$#tracks)
	{	my $h=$tracks[$track];
		next unless $h;
		my $f=($ref->[::SONG_LENGTH]<600)? '%01d:%02d' : '%02d:%02d';
		my $index=$h->{'index'}/75;
		$index=sprintf $f,$index/60,$index%60;
		$store->set($store->append,0,$track,1,$h->{title},2,$h->{performer},3,$index,4,PANGO_WEIGHT_NORMAL);
	}
}

1;
