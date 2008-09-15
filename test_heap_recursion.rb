
module TestHeap

=begin

CompiledMethod 17
  Nil
  -1
  1
  0
  InstructionSequence 70
    make_array 0                      (0)
    set_local 2                       (2)
    pop                               (4)
    check_argcount 1 1                (5)
    set_local_from_fp 0 0             (8)
    meta_push_0                       (11)
    push_local 0                      (12)
    send_stack 0 1                    (14)
    goto_if_false 22                  (17)
    meta_push_0                       (19)
    goto 38                           (20)
    meta_push_1                       (22)
    push_local 0                      (23)
    meta_send_op_minus                (25)
    push_local 0                      (26)
    make_array 1                      (28)
    push_local 2                      (30)
    send_stack 2 1                    (32)
    pop                               (35)
    goto 69                           (36)
    push_local 0                      (38)
    meta_send_op_plus                 (40)
    push_local 2                      (41)
    send_stack 3 0                    (43)
    goto_if_false 49                  (46)
    sret                              (48)
    push_local 2                      (49)
    send_stack 4 0                    (51)
    set_local 1                       (54)
    pop                               (56)
    push_int 0                        (57)
    push_local 1                      (59)
    send_stack 5 1                    (61)
    set_local 0                       (64)
    pop                               (66)
    goto 38                           (67)
    check_argcount 1 1                (69)
    set_local 0                       (72)
    pop                               (74)
    meta_push_0                       (75)
    push_local 0                      (76)
    send_stack 0 1                    (78)
    goto_if_false 86                  (81)
    meta_push_0                       (83)
    goto 102                          (84)
    meta_push_1                       (86)
    push_local 0                      (87)
    meta_send_op_minus                (89)
    push_local 0                      (90)
    make_array 1                      (92)
    push_local 2                      (94)
    send_stack 2 1                    (96)
    pop                               (99)
    goto 69                           (100)
    push_local 0                      (102)
    meta_send_op_plus                 (104)
    push_local 2                      (105)
    send_stack 3 0                    (107)
    goto_if_false 113                 (110)
    sret                              (112)
    push_local 2                      (113)
    send_stack 4 0                    (115)
    set_local 1                       (118)
    pop                               (120)
    push_int 0                        (121)
    push_local 1                      (123)
    send_stack 5 1                    (125)
    set_local 0                       (128)
    pop                               (130)
    goto 102                          (131)
  Symbol "fad"
  Symbol "/tmp/test4.rb"
  3
  Tuple 6
    SendSite "<="
    SendSite "fad"
    SendSite "<<"
    SendSite "empty?"
    SendSite "pop"
    SendSite "at"
  Tuple 3
    Tuple 1
      Symbol "n"
    Nil
    Nil
  Tuple 3
    Symbol "n"
    Symbol "__tmp__"
    Symbol "__locals__"
  Tuple 0
  Tuple 4
    Tuple 3
      5
      10
      11
    Tuple 3
      11
      18
      13
    Tuple 3
      19
      21
      14
    Tuple 3
      22
      133
      16
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
      n + fad(n - 1)  # __locals__ << [n]
    end
                      # __tmp__ = __locals__.pop
                      # n = __tmp__[0]
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

