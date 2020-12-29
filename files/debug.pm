# Copyright (C) 2005-2008 Quentin Sculo <squentin@free.fr>
#
# This file is part of Gmusicbrowser.
# Gmusicbrowser is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3, as
# published by the Free Software Foundation

=gmbplugin DEBUG
Debug
Debug plugin
=cut

package GMB::Plugin::DEBUG;
use strict;
use warnings;
use Gtk2;
use constant
{	OPT => 'PLUGIN_Debug_',
};
my ($textbuffer,$SourceView);
BEGIN
{	eval { require Gtk2::SourceView; };
	$SourceView= $@ ? 0 : 1;
}

sub Start
{	return if $textbuffer;
	if ($SourceView)
	{	my $lang = Gtk2::SourceView::LanguagesManager->new->get_language_from_mime_type('application/x-perl');
		$textbuffer=Gtk2::SourceView::Buffer->new_with_language($lang);
		$textbuffer->set('highlight', ::TRUE);
	}
	else {	$textbuffer=Gtk2::TextBuffer->new; }
	if (-r 'LoadmeinGMBdebug.pm')	#Look in the current dir
	{	open my($fh),'<','LoadmeinGMBdebug.pm' or return;
		my $code= do { local $/; <$fh> };
		close $fh;
		$textbuffer->set_text($code);
	}
}
sub Stop {}

sub prefbox
{	my $vbox=Gtk2::VBox->new;
	my $check=Gtk2::CheckButton->new('debug flag');
	$check->set_active(1) if $::debug;
	$check->signal_connect( toggled => sub {$::debug=$_[0]->get_active} );
	$vbox->pack_start($check,0,0,2);
	my $notebook=Gtk2::Notebook->new;
	$notebook->append_page(new_eval_box(), 'code');
	$notebook->append_page(new_widget_tree(), 'widgets');
	$vbox->add($notebook);
	return $vbox;
}

sub new_eval_box
{	my $vbox=Gtk2::VBox->new;
	my $textview= $SourceView ?	Gtk2::SourceView::View->new_with_buffer($textbuffer) :
					Gtk2::TextView->new_with_buffer($textbuffer);
	$textview->set_wrap_mode('char');
	$textview->modify_font( Gtk2::Pango::FontDescription->from_string('monospace') );
	my $sw=Gtk2::ScrolledWindow->new(undef,undef);
	$sw->set_shadow_type('etched-in');
	$sw->set_policy('automatic','automatic');
	$sw->add($textview);
	$vbox->add($sw);
	my $button=::NewIconButton( 'gtk-execute','eval',
	    sub	{	my $code=$textbuffer->get_text( $textbuffer->get_bounds, 1);
			return if $code eq '';
			my $time=times;
		    	eval $code;
			if ($@)	{warn "Error in debug command :\n$@";return;}
			warn "debug command took ".(times-$time)." s\n";
		});
	$vbox->pack_start($button,::FALSE,::FALSE,2);
	return $vbox;
}


sub new_widget_tree
{	my $vbox=Gtk2::VBox->new;
	my $store=Gtk2::TreeStore->new('Glib::String','Glib::String','Glib::String');
	my $treeview=Gtk2::TreeView->new($store);
	my $column=Gtk2::TreeViewColumn->new_with_attributes('widget', Gtk2::CellRendererText->new,'markup',0);
	$treeview->append_column($column);
	$column=Gtk2::TreeViewColumn->new_with_attributes('name', Gtk2::CellRendererText->new,'text',1);
	$treeview->append_column($column);
	my $sw=Gtk2::ScrolledWindow->new(undef,undef);
	$sw->set_shadow_type('etched-in');
	$sw->set_policy('automatic','automatic');
	$sw->add($treeview);
	my $label=Gtk2::Label->new;
	my $sw2=Gtk2::ScrolledWindow->new(undef,undef);
	$sw2->set_shadow_type('etched-in');
	$sw2->set_policy('automatic','automatic');
	$sw2->add_with_viewport($label);
	$label->set_selectable(1);
	$label->set_alignment(0,.5);
	$treeview->get_selection->signal_connect(changed=> sub
		{	my ($store,$iter)=$_[0]->get_selected;
			my $markup= $iter ? $store->get($iter,2) : '';
			$label->set_markup($markup);
		});
	my $button1=::NewIconButton( 'gtk-refresh','refresh',
	    sub	{	fill_treestore($treeview);
		});
	my $button2=::NewIconButton( 'gtk-index','pick widget',
	    sub	{	pick_widget($_[0],$treeview);
		});
	my $check=::NewPrefCheckButton(OPT.'show_nonlayout', 'Show non-layout windows',sub {fill_treestore($treeview)});
	my $bbox=Gtk2::HBox->new;
	my $paned=Gtk2::VPaned->new;
	$bbox->pack_start($_,0,0,2) for $button1,$button2,$check;
	$vbox->pack_start($bbox,0,0,2);
	$paned->pack1($sw,1,0);
	$paned->pack2($sw2,1,0);
	$vbox->add($paned);
	$treeview->signal_connect( realize => sub { Glib::Idle->add( sub { fill_treestore($treeview);0 }); } );
	return $vbox;
}

sub pick_widget
{	my ($widget,$treeview)=@_;
	my $win=$widget->get_toplevel;
	$widget->window->set_cursor(Gtk2::Gdk::Cursor->new('hand1'));
	Gtk2::Gdk->pointer_grab($win->window, 0, ['button-press-mask','button_release-mask'], undef, undef,0);
	my $handle; $handle=$win->signal_connect(button_press_event=> sub
		{	$widget->window->set_cursor(undef);
			$_[0]->signal_handler_disconnect($handle);
			Gtk2::Gdk->pointer_ungrab($_[1]->time);
			my @widgets=find_widget_under_pointer();
			#fill_treestore($treeview);
			select_widget($treeview, widget_string($widgets[0]) );
			warn "found more than 1 widget : @widgets\n" if @widgets>1;
			1;
		});
}

sub select_widget
{	my ($treeview,$widgetstring)=@_;
	$treeview->get_selection->unselect_all;
	return unless defined $widgetstring;
	my $store=$treeview->get_model;
	$store->foreach(sub
		{	my ($store,$path,$iter)=@_;
			my $name=$store->get($iter,0);
			return 0 unless $name eq $widgetstring;
			$treeview->expand_to_path($path);
			$treeview->get_selection->select_iter($iter);
			$treeview->scroll_to_cell($path, undef, ::TRUE, .5, 0);
			return 1;
		});
}

sub fill_treestore
{	my $treeview=shift;
	my $store=$treeview->get_model;
	my $iter=$treeview->get_selection->get_selected;
	my $selected= $iter ? $store->get($iter,0) : undef;
	$store->clear;
	my @toplevels=Gtk2::Window->list_toplevels;
	@toplevels=grep $_->isa('Layout::Window'),@toplevels  unless $::Options{OPT.'show_nonlayout'};
	my @todo;
	push @todo, undef,$_ for @toplevels;
	while (@todo)
	{	my $piter=shift @todo;
		my $widget=shift @todo;
		my $iter= $store->append($piter);
		my $ws=widget_string($widget);
		my $name=$widget->get_name;
		$name='' unless defined $name;
		my $info=get_widget_info($widget);
		if ($widget->isa('Gtk2::Container')) { push @todo,$iter,$_ for $widget->get_children; }
		$store->set($iter, 0,$ws, 1,$name, 2,$info);
	}
	if (my $iter=$store->get_iter_first)	# expand tree to first fork
	{	$iter=$store->iter_children($iter) while $store->iter_n_children($iter)==1;
		$treeview->expand_to_path( $store->get_path($iter) );
	}
	select_widget($treeview,$selected);
}
sub widget_string
{	my $w=shift;
	return undef unless $w;
	my $string="$w";
	$string=~s#=HASH\((.*)\)# <small>$1</small>#;
	return $string;
}
sub get_widget_info
{	my $w=shift;
	my $name=widget_string($w);
	my %prop=( map { $_, $w->get($_)} map $_->{name}, grep $_->{flags} >= 'readable', $w->list_properties );
	my $prop=join "\n", map "$_ = $prop{$_}", grep defined $prop{$_}, sort keys %prop;
	my $hash=join "\n", map "$_ = $w->{$_}", grep defined $w->{$_}, sort keys %$w;
	#my $alloc="allocation : ".join ",", $w->allocation->values;
	my $flags=join ' ',$w->get_flags;
	my $packing='';
	if (my $p=$w->parent)
	{	#  list_child_properties is not bound, so I have to do special cases
		if ($p->isa('Gtk2::Box')) { $packing='pack_type expand fill padding position' }
		elsif ($p->isa('Gtk2::Paned')) { $packing='resize shrink' }
		elsif ($p->isa('Gtk2::Fixed')) { $packing='x y' }
		elsif ($p->isa('Gtk2::Notebook')) { $packing='detachable menu-label position reorderable tab-expand tab-fill tab-label tab-pack' }
		elsif ($p->isa('Gtk2::Table')) { $packing='bottom-attach left-attach right-attach top-attach x-options x-padding y-options y-padding' }
		my @vals;
		for my $key (split / /,$packing)
		{	my $val=$p->child_get_property($w,$key);
			next unless defined $val;
			push @vals, "$key=$val";
		}
		$packing=join "\n",@vals;
	}
	#my $rcstyle=$w->get_modifier_style;
	#my $style='';
	#for my $state (qw/normal active prelight selected insensitive/)
	#{	my $s;
	#	my $rcflags=$rcstyle->color_flags($state);
	#	if ($rcflags >= 'fg')	{ $s.=' fg='.  $rcstyle->fg($state)->to_string }
	#	if ($rcflags >= 'bg')	{ $s.=' bg='.  $rcstyle->bg($state)->to_string }
	#	if ($rcflags >= 'text') { $s.=' text='.$rcstyle->text($state)->to_string }
	#	if ($rcflags >= 'base') { $s.=' base='.$rcstyle->base($state)->to_string }
	#	$style.=" state=$state ( $s )\n" if $s;
	#}
	#$style.="\nfont_desc=".	$rcstyle->font_desc	if defined $rcstyle->font_desc;
	#$style.="\nname=".	$rcstyle->name		if defined $rcstyle->name;
	my $suffix;
	if	($w->isa('Gtk2::Label')) { $suffix=$w->get_label; }
	elsif	($w->isa('Gtk2::Image') && $w->get_storage_type eq 'stock') { $suffix=($w->get_stock)[0]; }
	$name.=' "'.::PangoEsc($suffix).'"' if defined $suffix;
	my $markup=join "\n",	"<b><big>$name</big></b>",
				'<b>path=</b>',			::PangoEsc(($w->path)[0]),
				'<b>classpath=</b>',		::PangoEsc(($w->class_path)[0]),
		($hash ?	('<b>hash</b> :<small>',	::PangoEsc($hash).'</small>',	): ()),
		($packing ?	('<b>packing</b> :<small>',	::PangoEsc($packing).'</small>',): ()),
				#'<b>rcstyle</b> :<small>',	::PangoEsc($style).'</small>',
				'<b>flags</b> :<small>',	::PangoEsc($flags).'</small>',
				'<b>properties</b> :<small>',	::PangoEsc($prop).'</small>';
	return $markup;
}

sub find_widget_under_pointer
{	#my @todo= grep $_->isa('Layout::Window'), Gtk2::Window->list_toplevels;
	my ($gdkwin)=Gtk2::Gdk::Window->at_pointer;
	return unless $gdkwin;
	$gdkwin=$gdkwin->get_toplevel;
	my @todo=grep $_->window && $_->window==$gdkwin, Gtk2::Window->list_toplevels;
	my @found;
	while (my $wdgt=shift @todo)
	{	my ($x,$y)=$wdgt->get_pointer;
		my (undef,undef,$w,$h)=$wdgt->allocation->values;
		#warn "$wdgt $x $y\n";
		if ($x>=0 && $x<$w && $y>=0 && $y<$h)
		{	@found=grep !$wdgt->is_ancestor($_), @found;
			push @found,$wdgt;
		}
		#push @todo,$wdgt->get_children if $wdgt->isa('Gtk2::Container');
		next unless $wdgt->isa('Gtk2::Container');
		my @children=$wdgt->get_children;
		@children=( $wdgt->get_nth_page($wdgt->get_current_page) ) if $wdgt->isa('Gtk2::Notebook');
		push @todo,@children;
	}
	@found=grep $_->window && $_->window->is_visible && $_->window->is_viewable, @found;
	for my $w (@found)
	{	warn "$w\n  path=".($w->path)[0]."\n  classpath=".($w->class_path)[0]."\n";
	}
	#@found=grep $_->window==$gdkwin, @found;
	return @found;
}

1
