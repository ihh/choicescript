#!/usr/bin/perl -W

use Getopt::Long;
use Graph::Easy;
use Graph::Easy::Parser::Graphviz;
use Pod::Usage;

# parse options
my $man = 0;
my $help = 0;
my $start_node = "start";
my $create_scene_files = 0;
my $track_node_visits = 0;

GetOptions ('help|?' => \$help,
	    'man' => \$man,
	    'init=s' => \$start_node,
	    'scenes' => \$create_scene_files,
	    'track' => \$track_node_visits) or pod2usage(2);
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
my %edges_to;
for my $edge ($graph->edges()) {
    my ($from, $to, $attr) = ($edge->from()->name(), $edge->to()->name(), $edge->get_attributes());
    push @trans, [$from, $to, $attr];
    ++$edges_to{$to};
    if ($graph->is_undirected) {
	push @trans, [$to, $from, $attr];
	++$edges_to{$from};
    }
}

# ensure we have a start node
unless (grep ($_ eq $start_node, @node)) {
    # look for nodes with nothing incoming
    my @src_only = grep (!defined($edges_to{$_}), @node);
    if (@src_only == 1) {
	$start_node = $src_only[0];
    } else {
	warn
	    "Warning: initial node '$start_node' not found.\n",
	    "Node sequence will be random... better add a *goto\n";
    }
}

# ensure the start node is the first in @node, and therefore, the first in the scene
# (beyond this, the ordering of nodes in the choicescript file doesn't matter too much)
if (grep ($_ eq $start_node, @node)) {
    @node = ($start_node, grep ($_ ne $start_node, @node));
}

# sort transitions by source
my %choice;
grep (push(@{$choice{$_->[0]}}, [@$_[1,2]]), @trans);

# variables
my @vars;
if ($track_node_visits) {
    push @vars, "visits";
    push @vars, map ($_."_visits", @node);
}

# startup code
my @startup;
# create variables
my $create = $create_scene_files ? "*create" : "*temp";
push @startup, map ("$create $_", @vars);
push @startup, map ("*set $_ 0", @vars);

# loop over sources
for my $node (@node) {
    my @out;
    push @out, map (defined() ? "$_\n" : (),
		    $node eq $start_node ? @startup : (),
		    "\n*comment $node;",
		    $create_scene_files ? undef : "*label $node",
		    $track_node_visits ? ("*set ${node}_visits +1", "*set visits ${node}_visits") : (),
		    getAttr ($node_attr{$node}, "label", $track_node_visits ? "Currently: $node (visit #\${visits})." : "Currently: $node."));
    my $goto = $create_scene_files ? "*goto_scene" : "*goto";
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
    if ($create_scene_files) {
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

=item B<-track>

Track the number of visits to each node in a ChoiceScript variable ${node_visits}.

The first time the player visits the node, this variable will be 1; on the next visit, 2; and so on.

For convenience, this variable is also mirrored in ${visits} for the duration of the node.

=back

=head1 DESCRIPTION

B<graph2choice> will read a graph file in GraphViz DOT format and generate minimal stubs for a ChoiceScript scene.

In the GraphViz file, use 'label' node/edge attributes for narrative text, and 'tooltip' edge attribute for choice text.

=cut
