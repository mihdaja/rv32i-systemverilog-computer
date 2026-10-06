`timescale 1ns/1ps

import rv32i_pkg::*;

module reg_file_tb;

  logic        clk;
  logic        rst_n;
  logic        we;
  logic [4:0]  waddr;
  logic [31:0] wdata;
  logic [4:0]  raddr1;
  logic [4:0]  raddr2;
  logic [31:0] rdata1;
  logic [31:0] rdata2;

  int test_count = 0;
  int error_count = 0;
  int i;
  logic [4:0] next_raddr;

  // Clock generation: 100MHz (10ns period)
  always #5 clk = ~clk;

  // DUT instantiation
  reg_file dut (
    .clk(clk),
    .rst_n(rst_n),
    .we(we),
    .waddr(waddr),
    .wdata(wdata),
    .raddr1(raddr1),
    .raddr2(raddr2),
    .rdata1(rdata1),
    .rdata2(rdata2)
  );

  task check_reads(
    input string       test_name,
    input logic [31:0] exp_rdata1,
    input logic [31:0] exp_rdata2
  );
    test_count++;
    #1; // combinational settle
    if (rdata1 !== exp_rdata1 || rdata2 !== exp_rdata2) begin
      $display("[FAIL] %s: rdata1=0x%08h (exp 0x%08h), rdata2=0x%08h (exp 0x%08h)",
               test_name, rdata1, exp_rdata1, rdata2, exp_rdata2);
      error_count++;
    end else begin
      $display("[PASS] %s: rdata1=0x%08h, rdata2=0x%08h", test_name, rdata1, rdata2);
    end
  endtask

  initial begin
    $display("========================================");
    $display("Starting Register File Testbench");
    $display("========================================");

    clk = 0;
    rst_n = 0;
    we = 0;
    waddr = 0;
    wdata = 0;
    raddr1 = 0;
    raddr2 = 0;

    // 1. Reset check
    @(posedge clk);
    #1;
    check_reads("Reset state check (x0, x0)", 32'd0, 32'd0);

    raddr1 = 5'd1;
    raddr2 = 5'd31;
    check_reads("Reset state check (x1, x31)", 32'd0, 32'd0);

    // Release reset
    @(negedge clk);
    rst_n = 1;

    // 2. x0 hardwired to zero check
    @(posedge clk);
    #1;
    we = 1;
    waddr = 5'd0;
    wdata = 32'hDEAD_BEEF;
    @(posedge clk);
    #1;
    we = 0;
    raddr1 = 5'd0;
    raddr2 = 5'd0;
    check_reads("x0 write ignored (wdata=0xDEADBEEF)", 32'd0, 32'd0);

    // 3. Write and read across all registers x1 to x31
    for (i = 1; i < 32; i++) begin
      @(posedge clk);
      #1;
      we = 1;
      waddr = i[4:0];
      wdata = 32'hA000_0000 | (i * 32'h1001);
      @(posedge clk);
      #1;
      we = 0;
      raddr1 = i[4:0];
      raddr2 = 5'd0;
      check_reads($sformatf("Write & read back x%0d", i), 32'hA000_0000 | (i * 32'h1001), 32'd0);
    end

    // 4. Multiple register isolation check
    // Verify all registers still hold their specific values simultaneously
    for (i = 1; i < 32; i = i + 2) begin
      raddr1 = i[4:0];
      next_raddr = i + 1;
      raddr2 = (i + 1 < 32) ? next_raddr : 5'd0;
      #1;
      check_reads(
        $sformatf("Isolation check (x%0d, x%0d)", i, (i + 1 < 32) ? i + 1 : 0),
        32'hA000_0000 | (i * 32'h1001),
        (i + 1 < 32) ? (32'hA000_0000 | ((i + 1) * 32'h1001)) : 32'd0
      );
    end

    // 5. Write enable (we = 0) deassertion check
    @(posedge clk);
    #1;
    we = 0;
    waddr = 5'd5;
    wdata = 32'hFFFF_FFFF;
    @(posedge clk);
    #1;
    raddr1 = 5'd5;
    raddr2 = 5'd0;
    check_reads("WE=0 prevents overwriting x5", 32'hA000_0000 | (5 * 32'h1001), 32'd0);

    // 6. Overwrite check
    @(posedge clk);
    #1;
    we = 1;
    waddr = 5'd5;
    wdata = 32'h1234_5678;
    @(posedge clk);
    #1;
    we = 0;
    raddr1 = 5'd5;
    raddr2 = 5'd0;
    check_reads("Overwrite x5 with new value", 32'h1234_5678, 32'd0);

    // 7. Simultaneous read and write
    @(posedge clk);
    #1;
    we = 1;
    waddr = 5'd10;
    wdata = 32'hBEEF_CAFE;
    raddr1 = 5'd5; // reading x5 while writing x10
    raddr2 = 5'd10; // reading previous value of x10 before clock edge
    #1;
    check_reads("Combinational read during write setup (x5, x10-old)",
                32'h1234_5678,
                32'hA000_0000 | (10 * 32'h1001));
    @(posedge clk);
    #1;
    we = 0;
    check_reads("Read updated x10 after posedge clk",
                32'h1234_5678,
                32'hBEEF_CAFE);

    // 8. Asynchronous reset check mid-operation
    @(posedge clk);
    #1;
    rst_n = 0; // assert active-low reset asynchronously
    #1;
    raddr1 = 5'd5;
    raddr2 = 5'd10;
    check_reads("Async reset clears x5 and x10", 32'd0, 32'd0);

    $display("========================================");
    if (error_count == 0) begin
      $display("Register File Testbench PASSED (%0d tests)", test_count);
    end else begin
      $display("Register File Testbench FAILED (%0d errors out of %0d tests)", error_count, test_count);
    end
    $display("========================================");

    if (error_count != 0) $stop;
    $finish;
  end

endmodule
