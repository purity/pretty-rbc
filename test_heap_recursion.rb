
module TestHeap

=begin

CompiledMethod 17
  Nil
  -1
  1
  0
  InstructionSequence 58
    make_array 0                      (0)
    set_local 1                       (2)
    pop                               (4)
    check_argcount 1 1                (5)
    set_local_from_fp 0 0             (8)
    meta_push_0                       (11)
    push_local 0                      (12)
    send_stack 0 1                    (14)
    goto_if_false 22                  (17)
    meta_push_0                       (19)
    goto 39                           (20)
    meta_push_1                       (22)
    push_local 0                      (23)
    meta_send_op_minus                (25)
    push_local 0                      (26)
    push_local 1                      (28)
    send_stack 2 1                    (30)
    pop                               (33)
    goto 57                           (34)
    push_local 0                      (36)
    meta_send_op_plus                 (38)
    push_local 1                      (39)
    send_stack 3 0                    (41)
    goto_if_false 47                  (44)
    sret                              (46)
    push_local 1                      (47)
    send_stack 4 0                    (49)
    set_local 0                       (52)
    pop                               (54)
    goto 36                           (55)
    check_argcount 1 1                (57)
    set_local 0                       (60)
    pop                               (62)
    meta_push_0                       (63)
    push_local 0                      (64)
    send_stack 0 1                    (66)
    goto_if_false 74                  (69)
    meta_push_0                       (71)
    goto 91                           (72)
    meta_push_1                       (74)
    push_local 0                      (75)
    meta_send_op_minus                (77)
    push_local 0                      (78)
    push_local 1                      (80)
    send_stack 2 1                    (82)
    pop                               (85)
    goto 57                           (86)
    push_local 0                      (88)
    meta_send_op_plus                 (90)
    push_local 1                      (91)
    send_stack 3 0                    (93)
    goto_if_false 99                  (96)
    sret                              (98)
    push_local 1                      (99)
    send_stack 4 0                    (101)
    set_local 0                       (104)
    pop                               (106)
    goto 88                           (107)
  Symbol "fad"
  Symbol "/tmp/test4.rb"
  2
  Tuple 5
    SendSite "<="
    SendSite "fad"
    SendSite "<<"
    SendSite "empty?"
    SendSite "pop"
  Tuple 3
    Tuple 1
      Symbol "n"
    Nil
    Nil
  Tuple 2
    Symbol "n"
    Symbol "__locals__"
  Tuple 0
  Tuple 4
    Tuple 3
      5
      10
      126
    Tuple 3
      11
      18
      128
    Tuple 3
      19
      21
      129
    Tuple 3
      22
      109
      131
  Nil
  Nil
  Nil
  Nil

=end

  def self.fad(n)
                      # __locals__ = []
    if n <= 0
      0
    else
      n + fad(n - 1)  # __locals__ << n
    end
                      # if __locals__.empty?
                      #   <return>
                      # else
                      #   n = __locals__.pop
                      #   <resume>
  end

  def self.fib(n)
    if n <= 1
      n
    else
      fib(n - 2) + fib(n - 1)
    end
  end
end

num = 2_000

puts TestHeap.fad(num)

puts TestHeap.fib(10)

