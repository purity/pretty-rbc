
SELF_DIR = File.dirname(__FILE__) + '/'

module Main

  def self.infinite_dump_and_load_self

    cm = MethodContext.current.method
    str = PrettyCM.dump(cm)
    cm = PrettyCM.load(str)
    PrettyCM.write_file("#{SELF_DIR}main.pcm", str)
    puts "object_id: '#{cm.object_id}'"
    sleep(65)
    cm.as_script
  end

  def self.dump_others

    recurse = true
    src_dir  = ''
    dest_dir = ''
    activate_dest_dir = false
    activate_load = false

    PrettyCM.fetch_files(src_dir, recurse) do |file|
      if file =~ / \.rb \Z /x
        if file =~ / . /x
          cm = Compile.compile_file(file)
          str = PrettyCM.dump(cm)

          if activate_load
            cm = PrettyCM.load(str)
            str = PrettyCM.dump(cm)
          end

          file = PrettyCM.replace_suffix(file, '.rb', '.pcm')

          if activate_dest_dir
            file = dest_dir + file.gsub('/', '_')
          end

          if PrettyCM.read_file(file) != str
            PrettyCM.write_file(file, str)
            print "\n#{file}"
          else
            print '.'
          end
        end
      end
    end

    puts ''
  end

  def self.run_tail_call

    cm = Compile.compile_file("#{SELF_DIR}test_tail_call.rb")
    SelfTailCall.optimize(cm)
    #str = PrettyCM.dump(cm)
    #PrettyCM.write_file("#{SELF_DIR}test_tail_call.pcm", str)

    cm.as_script

    puts

    #cm = Compile.compile_file("#{SELF_DIR}test_indirect_tail_call.rb")
    #TailCall.optimize(cm)
    #str = PrettyCM.dump(cm)
    #PrettyCM.write_file("#{SELF_DIR}test_indirect_tail_call.pcm", str)

    #cm.as_script
  end

  def self.run_heap_recursion

    cm = Compile.compile_file("#{SELF_DIR}test_heap_recursion.rb")
    HeapRecursion.optimize(cm)
    #str = PrettyCM.dump(cm)
    #PrettyCM.write_file("#{SELF_DIR}test_heap_recursion.pcm", str)

    cm.as_script
  end
end

cm = MethodContext.current.method
ic = InstructionChanges.new(cm)
ic.test

#Main.infinite_dump_and_load_self
#Main.dump_others

Main.run_tail_call
Main.run_heap_recursion

