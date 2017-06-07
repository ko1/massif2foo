# usage:
#
#   $ valgrind --tool=massif --detailed-freq=1 --threshold=0.1 --stacks=yes --massif-out-file=massif.out.`date '+%s'` --max-snapshots=1000 [cmd] [args...]
#   $ ruby massif2foo.rb [--collect_key (file|func|line)] massif.out...
#

module MassifParser
  require 'optparse'
  $collect_key = :func_name
  $verbose = true
  $filter = nil

  OptionParser.new{|o|
    o.on('--collect_key [KEY]'){|o|
      case o.to_sym
      when :func, :file
        $collect_key = "#{o}_name".to_sym
      when :line
        $collect_key = :alloc_name
      end
    }
    o.on('--filter [FILTER]'){|o|
      $filter = /#{o}/
    }
    o.on('-q', '--quiet'){
      $verbose = false
    }
  }.parse!(ARGV)

  MAX_DEPTH = 5
  class Snapshot
    attr_reader :tree, :set, :nth

    def initialize nth
      STDERR.puts "## #{nth}" if $verbose
      @nth = nth
      @set = {}
      @tree = {
        :level => 0,
        :childs => {},
        :parent => nil,
      }
      @last_node = @tree
    end

    def add level, alloc_size, alloc_name
      level += 1
      return if MAX_DEPTH < level

      parent_node = @last_node
      while parent_node[:level] + 1 != level
        parent_node = parent_node[:parent]
      end

      if /(0x[0-9A-F]+): (.+) \((.+):(\d+)\)/ =~ alloc_name
        addr = $1
        func_name = $2
        file_name = $3
        line = $4
        # p [alloc_name, addr, func_name, file_name, line]
      elsif /(0x[0-9A-F]+): (.+) \((.+)\)/ =~ alloc_name
        addr = $1
        func_name = $2
        file_name = $3
        line = nil
      else
        # p alloc_name
      end

      node = {
        :level => level,
        :alloc_size => alloc_size,
        :alloc_name => alloc_name,
        :addr       => addr,
        :func_name  => func_name,
        :file_name  => file_name,
        :line       => line,
        :childs     => {},
        :parent     => parent_node,
      }
      parent_node[:childs][alloc_name] = node
      @last_node = node
    end
  end

  def self.parse massif_output
    snapshots = []
    snapshot = nil
    massif_output.each_line{|line|
      case line
      when /snapshot=(\d+)/
        snapshot = Snapshot.new($1.to_i)
        snapshots << snapshot
      when /^(time|mem_heap_B|mem_heap_extra_B|mem_stacks_B)=(\d+)/
        snapshot.set[$1] = $2.to_i
      when /^(heap_tree)=(.+)/
        snapshot.set[$1] = $2
      when /^(desc|cmd|time_unit):/, /^\#/
        # skip
      when /( *)n(\d+): (\d+) (.+)/
        level = $1.size
        siblings  = $2.to_i
        alloc_size = $3.to_i
        alloc_name = $4
        snapshot.add level, alloc_size, alloc_name
      else
        raise line.inspect
      end
    }
    snapshots
  end

  def self.to_table massif_output
    snapshots = parse(massif_output)

    stats = []
    default_cols  = ["nth", 'time', 'mem_heap_B', 'mem_heap_extra_B', 'mem_stacks_B']
    extra_cols = []

    STDERR.puts "## collect by #{$collect_key}"

    snapshots.each{|snapshot|
      stats << (stat = [snapshot.nth, snapshot.set['time'],
                        snapshot.set['mem_heap_B'],
                        snapshot.set['mem_heap_extra_B'],
                        snapshot.set['mem_stacks_B']])
      # collect
      collect_stat snapshot.tree, collected_stat = Hash.new(0), $collect_key
      extra_cols.each{|key|
        stat << (collected_stat[key] || 0)
        collected_stat.delete key
      }
      collected_stat.each{|k, v|
        next if $filter && $filter !~ k
        extra_cols << k
        stat << v
      }
    }
    [default_cols + extra_cols, stats]
  end

  def self.collect_stat node, result, key
    case node[:alloc_name]
    when nil, /objspace_xmalloc/, /objspace_xrealloc/, /ruby_xmalloc/, /ruby_xcalloc/, /ruby_xrealloc2/, /malloc\/new\/new/
      node[:childs].each{|name, node|
        collect_stat node, result, key
      }
    when /below massif/
      result['below_threshold'] += node[:alloc_size]
    else
      raise node[:alloc_name] unless node[key]

      case key
      when :func_name
        key_label = "#{node[:func_name]}@#{node[:file_name]}"
      when :file_name, :alloc_name
        key_label = node[key]
      end

      result[key_label] += node[:alloc_size]
    end
  end

  def self.to_tsv massif_output
    cols, lines = to_table(massif_output)
    puts cols.map{|item| item.gsub(/\s+/, '_')}.join("\t")
    lines.each{|line|
      puts line.join("\t")
    }
  end
end

if $0 == __FILE__
  MassifParser.to_tsv(ARGF)
end
