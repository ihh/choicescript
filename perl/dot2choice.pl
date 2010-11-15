#!/usr/bin/perl -W

# print usage
if (grep (/^-h/, @ARGV)) {
    die
	"\nUsage: $0 <dot file>\n\n",
	"Converts graphviz dot-format files into ChoiceScript stubs.\n\n",
	"Currently a bit picky about the input format (one edge per line is safest).\n",
	"Probably best to to filter input through 'dot -Tdot' to clean it up\n",
	"(although this program may then get confused about the ordering of nodes)\n\n",
	"Use 'label' node/edge attributes for narrative text,\n",
	"and 'tooltip' edge attribute for choice text.\n\n";
}

# read file
my @dot = <>;
grep (chomp, @dot);

# parse file
my $nameRegex = '[A-Za-z_][A-Za-z_\d]*';
my $nameListRegex = '[A-Za-z0-9_\s]+?';
my $transRegex = '^\s*('.$nameRegex.'?)\s*\->\s*('.$nameRegex.')\s*(.*?)\s*;?\s*$';
my $multiRegex = '^\s*('.$nameRegex.'?)\s*\->\s*\{\s*('.$nameListRegex.')\s*\}\s*(.*?)\s*;?\s*$';
my $nodeRegex = '^\s*('.$nameRegex.')\s*(.*?)\s*;?\s*$';
my $keywordRegex = '^\s*(node|edge|graph|digraph)\b';
my $assignRegex = '^\s*'.$nameRegex.'\s*=';

# get all relevant lines from file
my @lines = grep ($dot[$_] !~ /$keywordRegex/
		  && $dot[$_] !~ /$assignRegex/
		  && ($dot[$_] =~ /$transRegex/
		      || $dot[$_] =~ /$multiRegex/
		      || $dot[$_] =~ /$nodeRegex/),
		  0..$#dot);

# single transitions
my @trans;
for my $src_dest_attr_lnum (map ($dot[$_] =~ /$transRegex/ ? [$1,$2,$3,$_] : () , @lines)) {
    my ($src, $dest, $attr, $lnum) = @$src_dest_attr_lnum;
    my @dest;
    while (1) {
	push @dest, $dest;
	last unless "$dest $attr" =~ /$transRegex/;  # unpack chains like a->b->c->d
	($dest, $attr) = ($2, $3);
    }
    for my $d (@dest) { push @trans, [$src,$d,$attr,$lnum]; $src = $d; $lnum += 1/@dest; }
}

# unpack multiple transitions like a->{b c}
for my $src_dest_attr_lnum (map ($dot[$_] =~ /$multiRegex/ ? [$1,$2,$3,$_] : () , @lines)) {
    my ($src, $dests, $attr, $lnum) = @$src_dest_attr_lnum;
    my @dest = split /\s+/, $dests;
    for my $dest (@dest) { push @trans, [$src,$dest,$attr,$lnum]; $lnum += 1/@dest }
}

# nodes
my @node_lines = grep ($dot[$_] !~ /$transRegex/ && $dot[$_] !~ /$multiRegex/, @lines);
my %node_attr = map ($dot[$_] =~ /$nodeRegex/ ? ($1=>$2) : (), @node_lines);
for my $src_dest (@trans) {
    my ($src, $dest) = @$src_dest;
    $node_attr{$src} = "" unless exists $node_attr{$src};
    $node_attr{$dest} = "" unless exists $node_attr{$dest};
}
my @node = keys %node_attr;

# ensure the first node mentioned in the dotfile is the first in @node, and therefore, the first in the scene
# (beyond this, the ordering of nodes in the choicescript file doesn't matter too much)
if (@lines) {
    my $first;
    if ($dot[$lines[0]] =~ /$transRegex/) {
	$first = $1;
    } elsif ($dot[$lines[0]] =~ /$nodeRegex/) {
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
grep (push(@{$choice{$_->[0]}}, [@$_[1,2,3]]), @trans);

# loop over sources
for my $node (@node) {
    print map ("$_\n",
	       "*comment $node;",
	       "*label $node",
	       getAttr ($node_attr{$node}, "label", "Currently: $node."));
    if (defined $choice{$node} && @{$choice{$node}} > 1) {
	print "*choice\n";
	my @choices = sort { $a->[2] <=> $b->[2] } @{$choice{$node}};
	for my $dest_attrs_lnum (@choices) {
	    my ($dest, $attrs, $lnum) = @$dest_attrs_lnum;
	    my $tip = getAttr ($attrs, "tooltip", "$dest");
	    my $label = getAttr ($attrs, "label", "You choose $dest.");
	    print map ("  $_\n",
		       "*comment $node -> $dest;   // line " . int($lnum+1),
		       "#$tip",
		       "  $label",
		       "  *page_break",
		       "  *goto $dest",
		       "");
	}
	print "\n";
    } elsif (defined $choice{$node} && @{$choice{$node}} == 1) {
	my ($dest, $attrs, $lnum) = @{$choice{$node}->[0]};
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
