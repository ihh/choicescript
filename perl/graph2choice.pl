#!/usr/bin/perl -W

use Getopt::Long;
use Graph::Easy;
use Graph::Easy::Parser::Graphviz;
use Pod::Usage;

# parse options
my $man = 0;
my $help = 0;
my $startScene = "start";
my $createSceneFiles = 0;

GetOptions ('help|?' => \$help,
	    'man' => \$man,
	    'init=s' => \$startScene,
	    'scenes' => \$createSceneFiles) or pod2usage(2);
pod2usage(1) if $help;
pod2usage(-exitstatus => 0, -verbose => 2) if $man;

# read file
my $parser = Graph::Easy::Parser::Graphviz->new();
if (@ARGV != 1) { warn "Please specify a filename!\n"; pod2usage(2) }
my ($dotfile) = @ARGV;
my $graph = $parser->from_file($dotfile);

# extract nodes & edges
my %node_attr;
for my $node ($graph->nodes()) {
    $node_attr{$node->name()} = $node->get_attributes();
}

my @node = keys %node_attr;

my @trans;
for my $edge ($graph->edges()) {
    push @trans, [$edge->from()->name(), $edge->to()->name(), $edge->get_attributes()];
}

# ensure the start node is the first in @node, and therefore, the first in the scene
# (beyond this, the ordering of nodes in the choicescript file doesn't matter too much)
unless ($createSceneFiles) {  # this is all irrelevant if we're creating files, which are unordered
    if (grep ($_ eq $startScene, @node)) {
	@node = ($startScene, grep ($_ ne $startScene, @node));
    } else {
	warn "Warning: initial node '$startScene' not found.\n", "Order in which nodes are output may be random\n";
    }
}

# sort transitions by source
my %choice;
grep (push(@{$choice{$_->[0]}}, [@$_[1,2]]), @trans);

# loop over sources
for my $node (@node) {
    my @out;
    push @out, map (defined() ? "$_\n" : (),
		    "*comment $node;",
		    $createSceneFiles ? undef : "*label $node",
		    getAttr ($node_attr{$node}, "label", "Currently: $node."));
    my $goto = $createSceneFiles ? "*goto_scene" : "*goto";
    if (defined $choice{$node} && @{$choice{$node}} > 1) {
	push @out, "*choice\n";
	my @choices = @{$choice{$node}};
	for my $dest_attrs (@choices) {
	    my ($dest, $attrs) = @$dest_attrs;
	    my $tip = getAttr ($attrs, "title", "$dest");  # graphviz 'tooltip' gets converted to Graph::Easy 'title'
	    my $label = getAttr ($attrs, "label", "You choose $dest.");
	    push @out, map (defined() ? "  $_\n" : (),
			    "*comment $node -> $dest;",
			    "#$tip",
			    "  $label",
			    "  *page_break",
			    "  $goto $dest",
			    "");
	}
	push @out, "\n";
    } elsif (defined $choice{$node} && @{$choice{$node}} == 1) {
	my ($dest, $attrs) = @{$choice{$node}->[0]};
	my $tip = getAttr ($attrs, "title", undef);  # graphviz 'tooltip' gets converted to Graph::Easy 'title'
	my $label = getAttr ($attrs, "label", "Next: $dest.");
	push @out, map (defined() ? "$_\n" : (),
			"",
			"*line_break",
			"*comment $node -> $dest;",
			$tip,
			$label,
			"*page_break",
			"$goto $dest",
			"");
    } else {
	push @out, "*finish\n\n";
    }
    # write output
    if ($createSceneFiles) {
	local *SCENE;
	open SCENE, ">$node.txt" or die "Couldn't create $node.txt: $!";
	print SCENE @out;
	close SCENE or die "Couldn't write $node.txt: $!";
    } else {
	print @out;
    }
}

# and that's it
exit;

# subroutine to extract attribute values & unescape newlines
sub getAttr {
    my ($attrHashRef, $attr, $default) = @_;
    my $val;
    $val = $attrHashRef->{$attr} if exists($attrHashRef->{$attr});
    $val = $default unless defined($val) && length($val) > 1;
    $val =~ s/\\n/\n/g if defined $val;
    return $val;
}

__END__

=head1 NAME

graph2choice.pl - convert GraphViz files to ChoiceScript

=head1 SYNOPSIS

graph2choice.pl [options] <graph file>

  Options:
    -help,-?         brief help message
    -man             full documentation
    -init <name>     specify initial node
    -scenes          create scene files

=head1 OPTIONS

=over 8

=item B<-help>

Print a brief help message and exits.

=item B<-man>

Prints the manual page and exits.

=item B<-init>

Specify the name of the initial node in the graph (i.e. where the choicescript scene begins).

If no value is specified, the program will look for a node named 'start'.

=item B<-scenes>

Create multiple scene files, connected by *goto_scene.

This option overrides the default behavior, which is to print one monolithic stream of choicescript to standard output, containing multiple *label's connected by *goto.

=back

=head1 DESCRIPTION

B<graph2choice> will read a graph file in GraphViz format and generate stubs for a ChoiceScript scene.

In the GraphViz file, use 'label' node/edge attributes for narrative text, and 'tooltip' edge attribute for choice text.

=cut
