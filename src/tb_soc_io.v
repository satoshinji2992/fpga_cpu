`timescale 1ns/1ps
module tb_soc_io;
    localparam CLKS_PER_BIT=16, LOG_SIZE=2048;
    reg clk=0, rst_n=0, uart_rx_line=1;
    reg key1=1, key2=1, key3=1, key4=1;
    wire uart_tx, led1,led2,led3,led4;
    wire sh_clk,sh_cke,sh_ncs,sh_nwe,sh_ncas,sh_nras;
    wire sl_clk,sl_cke,sl_ncs,sl_nwe,sl_ncas,sl_nras;
    wire [1:0] sh_dqm,sh_ba,sl_dqm,sl_ba;
    wire [12:0] sh_a,sl_a;
    wire [15:0] sh_db,sl_db;
    wire [31:0] dq={sh_db,sl_db};
    reg model_oe=0;
    reg [31:0] model_dq=0;
    reg [31:0] mem[0:32767];
    reg [12:0] open_row[0:3];
    reg [14:0] read_index;
    reg [2:0] read_count=0;
    integer i,log_len=0,fails=0,sdram_reads=0,sdram_writes=0;
    reg [7:0] log[0:LOG_SIZE-1];
    wire [7:0] cap_data;
    wire cap_valid;
    assign {sh_db,sl_db}=model_oe ? model_dq : 32'bz;

    top #(.CLK_FREQ(1600000),.BAUD(100000)) dut(
        .clk(clk),.rst_n(rst_n),.key1(key1),.key2(key2),.key3(key3),.key4(key4),
        .uart_rx(uart_rx_line),.uart_tx(uart_tx),.led1(led1),.led2(led2),.led3(led3),.led4(led4),
        .sh_clk(sh_clk),.sh_cke(sh_cke),.sh_ncs(sh_ncs),.sh_nwe(sh_nwe),.sh_ncas(sh_ncas),.sh_nras(sh_nras),
        .sh_dqm(sh_dqm),.sh_ba(sh_ba),.sh_a(sh_a),.sh_db(sh_db),
        .sl_clk(sl_clk),.sl_cke(sl_cke),.sl_ncs(sl_ncs),.sl_nwe(sl_nwe),.sl_ncas(sl_ncas),.sl_nras(sl_nras),
        .sl_dqm(sl_dqm),.sl_ba(sl_ba),.sl_a(sl_a),.sl_db(sl_db));
    uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) capture(.clk(clk),.rst_n(rst_n),.rx(uart_tx),.data(cap_data),.valid(cap_valid));
    always #5 clk=~clk;
    always @(posedge clk) if(cap_valid && log_len<LOG_SIZE) begin log[log_len]=cap_data; log_len=log_len+1; end

    // x32 command model driven from the SH command/address set.
    always @(posedge sh_clk) begin
        if(read_count!=0) begin
            read_count<=read_count-1;
            if(read_count==1) begin model_dq<=mem[read_index]; model_oe<=1; end
        end else if(model_oe) model_oe<=0;
        if(sh_cke && !sh_ncs) case({sh_nras,sh_ncas,sh_nwe})
            3'b011: open_row[sh_ba]<=sh_a;
            3'b101: begin read_index<={open_row[sh_ba][5:0],sh_a[8:0]}; read_count<=2; sdram_reads=sdram_reads+1; end
            3'b100: begin
                sdram_writes=sdram_writes+1;
                if(!sl_dqm[0]) mem[{open_row[sh_ba][5:0],sh_a[8:0]}][7:0]<=dq[7:0];
                if(!sl_dqm[1]) mem[{open_row[sh_ba][5:0],sh_a[8:0]}][15:8]<=dq[15:8];
                if(!sh_dqm[0]) mem[{open_row[sh_ba][5:0],sh_a[8:0]}][23:16]<=dq[23:16];
                if(!sh_dqm[1]) mem[{open_row[sh_ba][5:0],sh_a[8:0]}][31:24]<=dq[31:24];
            end
            default: begin end
        endcase
    end

    task send_byte(input [7:0] b); integer k; begin
        uart_rx_line=0; repeat(CLKS_PER_BIT) @(posedge clk);
        for(k=0;k<8;k=k+1) begin uart_rx_line=b[k]; repeat(CLKS_PER_BIT) @(posedge clk); end
        uart_rx_line=1; repeat(CLKS_PER_BIT*20) @(posedge clk);
    end endtask
    task send_sdram; begin send_byte("s");send_byte("d");send_byte("r");send_byte("a");send_byte("m");send_byte(10); end endtask
    task send_irq; begin send_byte("i");send_byte("r");send_byte("q");send_byte(10); end endtask
    task send_paint; begin send_byte("p");send_byte("a");send_byte("i");send_byte("n");send_byte("t");send_byte(10); end endtask
    function integer has_text(input [8*24-1:0] text,input integer len); integer a,b,ok; begin
        has_text=0;
        for(a=0;a+len<=log_len;a=a+1) begin ok=1; for(b=0;b<len;b=b+1) if(log[a+b]!==text[(len-1-b)*8 +: 8]) ok=0; if(ok) has_text=1; end
    end endfunction
    function integer has_painted_frame; input integer unused; integer a,b,ok; begin
        has_painted_frame=0;
        for(a=0;a+133<log_len;a=a+1) begin
            if(log[a]===8'hA5 && log[a+1]==="D" && log[a+2]===8'd131 &&
               log[a+3]===8'd1 && log[a+4]===8'd0 && log[a+5]===8'd0 &&
               log[a+6]===8'd1 && log[a+7]===8'd2) begin
                ok=1;
                for(b=2;b<128;b=b+1)
                    if(log[a+6+b]!==8'd0) ok=0;
                if(ok) has_painted_frame=1;
            end
        end
    end endfunction

    initial begin
        for(i=0;i<32768;i=i+1) mem[i]=0;
        repeat(20) @(posedge clk); rst_n=1;
        repeat(30000) @(posedge clk);
        send_sdram();
        repeat(12000) @(posedge clk);
        key1=0; repeat(20) @(posedge clk); key1=1;
        repeat(3000) @(posedge clk);
        send_irq();
        repeat(15000) @(posedge clk);
        send_paint();
        repeat(3000000) @(posedge clk);
        send_byte("x");
        repeat(200000) @(posedge clk);
        send_byte("d");
        repeat(200000) @(posedge clk);
        send_byte("q");
        repeat(30000) @(posedge clk);
        if(!has_text("SDRAM PASS",10)) begin $display("missing SDRAM PASS"); fails=fails+1; end
        if(!has_text("irq uart=0x",11)) begin $display("missing IRQ report"); fails=fails+1; end
        if(!has_text("SDRAM paint",11)) begin $display("missing SDRAM paint banner"); fails=fails+1; end
        if(!has_painted_frame(0)) begin $display("missing painted-pixel binary frame"); fails=fails+1; end
        if(sdram_writes < 32771 || sdram_reads < 130) begin
            $display("insufficient paint SDRAM traffic reads=%0d writes=%0d",sdram_reads,sdram_writes);
            fails=fails+1;
        end
        if(dut.data_mem_b0[29]!==8'h01) begin $display("key IRQ count=%02h",dut.data_mem_b0[29]); fails=fails+1; end
        if(fails==0) $display("SOC SDRAM/INTERRUPT PASS"); else begin
            $display("SOC SDRAM/INTERRUPT FAIL %0d irq_en=%b irq_pnd=%b pc=%08h ifid_pc=%08h ifid_instr=%08h core_mstatus=%08h mie=%08h mem0=%08h mem1=%08h sdram_rdata=%08h reads=%0d writes=%0d t0=%08h t1=%08h t2=%08h t3=%08h",fails,dut.irq_enable,dut.irq_pending_mmio,dut.u_cpu.pc_reg,dut.u_cpu.ifid_pc,dut.u_cpu.ifid_instr,dut.u_cpu.csr_mstatus,dut.u_cpu.csr_mie,mem[0],mem[1],dut.sdram_rdata,sdram_reads,sdram_writes,dut.u_cpu.regs[5],dut.u_cpu.regs[6],dut.u_cpu.regs[7],dut.u_cpu.regs[28]);
            $write("--- UART LOG ---\n"); for(i=0;i<log_len;i=i+1) $write("%c",log[i]); $write("\n--- END ---\n");
        end
        $finish;
    end
endmodule
