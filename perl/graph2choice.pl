#!/usr/bin/perl -W

use Getopt::Long;
use Graph::Easy;
use Graph::Easy::Parser::Graphviz;
use Pod::Usage;

# parse options
my $man = 0;
my $help = 0;
my $startScene = undef;

GetOptions('help|?' => \$help, man => \$man, 'start=s' => \$startScene) or pod2usage(2);
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
if (defined $startScene) {
    if (grep ($_ eq $startScene, @node)) {
	@node = ($startScene, grep ($_ ne $startScene, @node));
    } else {
	warn "Warning: starting node '$startScene' not found\n";
    }
}

# create dummy name for last scene
my $endScene = "next_scene";
while (exists $node_attr{$endScene}) { $endScene .= "_" }

# sort transitions by source
my %choice;
grep (push(@{$choice{$_->[0]}}, [@$_[1,2]]), @trans);

# loop over sources
for my $node (@node) {
    print map ("$_\n",
	       "*comment $node;",
	       "*label $node",
	       getAttr ($node_attr{$node}, "label", "Currently: $node."));
    if (defined $choice{$node} && @{$choice{$node}} > 1) {
	print "*choice\n";
	my @choices = @{$choice{$node}};
	for my $dest_attrs (@choices) {
	    my ($dest, $attrs) = @$dest_attrs;
	    my $tip = getAttr ($attrs, "title", "$dest");  # graphviz 'tooltip' gets converted to Graph::Easy 'title'
	    my $label = getAttr ($attrs, "label", "You choose $dest.");
	    print map ("  $_\n",
		       "*comment $node -> $dest;",
		       "#$tip",
		       "  $label",
		       "  *page_break",
		       "  *goto $dest",
		       "");
	}
	print "\n";
    } elsif (defined $choice{$node} && @{$choice{$node}} == 1) {
	my ($dest, $attrs) = @{$choice{$node}->[0]};
	my $label = getAttr ($attrs, "label", "You choose $dest.");
	print map ("$_\n",
		   "*line_break",
		   "*comment $node -> $dest;",
		   $label,
		   "*page_break",
		   "*goto $dest",
		   "");
    } else {
	print "*goto $endScene\n\n";
    }
}

# print dummy last scene
print "*label $endScene\n", "*finish\n";

# and that's it
exit;

# subroutine to extract attribute values & unescape newlines
sub getAttr {
    my ($attrHashRef, $attr, $default) = @_;
    my $val;
    $val = $attrHashRef->{$attr} if exists($attrHashRef->{$attr});
    $val = $default unless defined($val) && length($val) > 1;
    $val =~ s/\\n/\n/g;
    return $val;
}

__END__

=head1 NAME

graph2choice - convert GraphViz files to ChoiceScript

=head1 SYNOPSIS

graph2choice [options] <graph file>

  Options:
    -help,-?         brief help message
    -man             full documentation
    -start <name>    specify starting node

=head1 OPTIONS

=over 8

=item B<-help>

Print a brief help message and exits.

=item B<-man>

Prints the manual page and exits.

=item B<-start>

Specify the name of the starting node in the graph (i.e. where the choicescript scene begins).

=back

=head1 DESCRIPTION

B<graph2choice> will read a graph file in GraphViz format and generate stubs for a ChoiceScript scene.

In the GraphViz file, use 'label' node/edge attributes for narrative text, and 'tooltip' edge attribute for choice text.

=cut
