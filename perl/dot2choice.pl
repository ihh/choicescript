#!/usr/bin/perl -W

# print usage
if (grep (/^-h/, @ARGV)) {
    die
	"\nUsage: $0 <dot file>\n\n",
	"Converts graphviz dot-format files into ChoiceScript stubs.\n",
	"Use 'label' node/edge attributes for narrative text,\n",
	"and 'tooltip' edge attribute for choice text.\n\n";
}

# read file
my @dot = <>;
grep (chomp, @dot);

# parse file
my $transRegex = '^\s*(\S+?)\s*\->\s*([^\s\[\-;]+)\s*(.*?)\s*;?\s*$';
my $nodeRegex = '^\s*([^\s\[;]+)\s*(.*?)\s*;?\s*$';
my @lines = grep (/$transRegex/ || (!/^\s*(node|edge|graph|digraph)\s+/ && !/^\s*\S*?[=\{\}]/), @dot);

my @trans = map (/$transRegex/ ? [$1,$2,$3] : () , @lines);
my %node_attr = (map (/$nodeRegex/ ? ($1=>$2) : (),
		      grep (!/\->/, @lines)),
		 map (($_->[0] => ""), @trans));
my @node = keys %node_attr;

# ensure the first node mentioned in the dotfile is the first in @node, and therefore, the first in the scene
if (@lines) {
    my $first;
    if ($lines[0] =~ /$transRegex/) {
	$first = $1;
    } elsif ($lines[0] =~ /$nodeRegex/) {
	$first = $1;
    }
    if (defined $first) {
	@node = ($first, grep ($_ ne $first, @node));
    }
}

# Commented-out code dumps out the original graph, complete with node/edge attributes
#warn "// Original graph file\n", "digraph {\n";
#warn "// Nodes\n", map("$_ $node_attr{$_};\n",@node);
#warn "// Transitions\n", map("$$_[0] -> $$_[1] $$_[2];\n",@trans);
#warn "}\n";

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
	       getAttr ($node_attr{$node}, "label", "This is $node."));
    if (defined $choice{$node} && @{$choice{$node}} > 1) {
	print "*choice\n";
	for my $dest_attrs (@{$choice{$node}}) {
	    my ($dest, $attrs) = @$dest_attrs;
	    my $tip = getAttr ($attrs, "tooltip", "$dest");
	    my $label = getAttr ($attrs, "label", "You choose $dest.");
	    print map ("  $_\n",
		       "*comment $node -> $dest;",
		       "#$tip",
		       $label,
		       "*goto $dest",
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

# subroutine to extract attribute values
sub getAttr {
    my ($attrText, $attr, $default) = @_;
    my $val = $default;
    if ($attrText =~ /\b$attr\s*=\s*\"([^\"]+)\"/) { $val = $1 }
    elsif ($attrText =~ /\b$attr\s*=\s*([^\s,]+)/) { $val = $1 }
    $val =~ s/\\n/\n/g;
    return $val;
}
