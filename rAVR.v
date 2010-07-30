
// http://marsohod.org 
// see full project description at http://www.marsohod.org/index.php/projects/66-makeavr
// Reduced AVRCore, Verilog HDL
// tested on MARSOHOD development board!

// ������ ���������� ������ ���� AVR ��������������� ��� Altera CPLD MAX2

module rAVR(
	input wire reset,
	input wire clk,

	//UFM (User Flash Memory) interface
	//��������� � ���� ������ UFM, ������� ��������� ������ ���� MAX2
	//���� ������ - ����������������, � ������ � ������ ���������� ���������� ����������

	//address
	//������� ���������� ������� UFM
	output wire arclkena,
	output wire arclkshift,
	output wire ardout,

	//data
	//������� ��� ������ ���������������� ������ �� UFM
	input  wire drdin,
	output wire drshift,

	//interface to PIO ports
	//����������, �������� ����� ��������� ��������������� - ��� ��� �����
	output reg  [7:0]port0, //typically connect to LEDs
							//������, �� ����� ��������, ���������� ���� 8 �����������
	output reg  [7:0]port1, //typically attached to motors
							//������, �� ����� ��������, ��������� ���� ������� ���������
	input  wire [7:0]port2  //connect to Buttons and other inputs
							//������, �� ����� ��������, ���������� ���� ����� ������� ��������
);

//opcode read from UFM
//��� ���������� ����������, ��������� �� ���� UFM
reg [15:0]opcode;

//instruction pointer
//��������� �� ������� �������� ���������� � ���� ������
reg [8:0]ip;

//four common purpose registers
//������ �������� ������ ����������
reg [7:0]register[3:0];

//ALU operands
//��������, ���� ���������� �������� ��� ������������ ����������
reg [7:0]alu_operand0;
reg [7:0]alu_operand1;
reg [2:0]alu_cmd;

reg [2:0]sel_cmd;
reg [7:0]alu_result;

//����� ��� �������� ���������
reg flag_z;
reg flag_c;
 
reg flag_z_fixed;
reg flag_c_fixed;

//������� "�����" ����� ���� ����������� � ���� �������
reg sel_imm;
wire [7:0]immediate; assign immediate = { opcode[11:8],opcode[3:0] };

//get operand from register pool according to opcode source register index
//����� �������� ���������
wire [2:0]src_reg_idx;  assign src_reg_idx = opcode[2:0];
reg [7:0]source_val;
always @*
begin
	case(src_reg_idx)
	0: source_val = register[0];
	1: source_val = register[1];
	2: source_val = register[2];
	3: source_val = register[3];
	4: source_val = port0;
	5: source_val = port1;
	6: source_val = port2;
	7: source_val = port2;
	endcase
end

//get operand from register pool according to opcode destination register index
//����� �������� ���������
wire [2:0]dest_reg_idx; assign dest_reg_idx = opcode[6:4];
reg [7:0]dest_val;
always @*
begin
	case(dest_reg_idx)
	0: dest_val = register[0];
	1: dest_val = register[1];
	2: dest_val = register[2];
	3: dest_val = register[3];
	4: dest_val = port0;
	5: dest_val = port1;
	6: dest_val = port2;
	7: dest_val = port2;
	endcase
end

//���������� �������� ������ ALU (����������-����������� ����������)
parameter CMD_LSR = 3'b000;
parameter CMD_CP  = 3'b001;
parameter CMD_SUB = 3'b010;
parameter CMD_ADD = 3'b011;
parameter CMD_AND = 3'b100;
parameter CMD_EOR = 3'b101;
parameter CMD_OR  = 3'b110;
parameter CMD_MOV = 3'b111;

//decode fetched operation
//select operands and unify commands (i.e. CP and CPI are similar, SUB and SUBI are similar etc..)
//����������� ���� �������� � ���������� ������� ������ � ������� �����������
//��������: ������� SUBI ���-�� ������ �� SUB
//��������! ������������ ������ ���������/�������� �������������!
//����������� ������������� ������ �������� ������!
always @*
begin
	if( (opcode[15:14]==2'b00) && (opcode[13:12]!=2'b11) )
	begin
		sel_imm = 1'b0;
		sel_cmd = {opcode[13],opcode[11:10]};
	end
	else
	if(opcode[15:14]==2'b10)
	begin
		sel_imm = 1'b0;
		sel_cmd = 3'b000;
	end
	else
	begin
		sel_imm = 1'b1;
		case(opcode[15:12])
		4'b0101: sel_cmd = CMD_SUB;
		4'b0111: sel_cmd = CMD_AND;
		4'b0110: sel_cmd = CMD_OR;
		4'b0011: sel_cmd = CMD_CP;
		4'b1110: sel_cmd = CMD_MOV;
		default: sel_cmd = CMD_CP;
		endcase
	end
end

//fix decoded command
//������������� �������� ��� ����������
always @(posedge clk or posedge reset)
begin
	if(reset)
	begin
		alu_operand0 <= 0;
		alu_operand1 <= 0;
		alu_cmd <= 0;
	end
	else
	begin
		if(opcode_ready)
		begin
			alu_operand0 <= dest_val;
			
			if(sel_imm)
				alu_operand1 <= immediate;
			else
				alu_operand1 <= source_val;
				
			alu_cmd <= sel_cmd;
		end
	end
end

//ALU
//����������-���������� ����������
always @*
begin
	case(alu_cmd)
		CMD_CP,
		CMD_SUB: 
			begin
				{ flag_c, alu_result } = alu_operand0 - alu_operand1; 
				flag_z = ~(|alu_result); 
			end
		CMD_AND: 
			begin
				alu_result = alu_operand0 & alu_operand1;
				flag_z = ~(|alu_result);
				flag_c = flag_c_fixed; //flag C not changed
			end
		CMD_OR:
			begin
				alu_result = alu_operand0 | alu_operand1;
				flag_z = ~(|alu_result);
				flag_c = flag_c_fixed; //flag C not changed
			end
		CMD_MOV:
			begin
				alu_result = alu_operand1;
				flag_c = flag_c_fixed;
				flag_z = flag_z_fixed;
			end
		CMD_ADD:
			begin
				{ flag_c, alu_result } = alu_operand0 + alu_operand1;
				flag_z = ~(|alu_result);
			end
		CMD_EOR:
			begin
				alu_result = alu_operand0 ^ alu_operand1;
				flag_c = flag_c_fixed; //flag C not changed
				flag_z = ~(|alu_result);
			end
		CMD_LSR:
			begin
				alu_result = alu_operand0 >>  1;
				flag_c = alu_operand0[0];
				flag_z = ~(|alu_result);
			end
		endcase
end

//���������� ���������� ���������� ALU � �������-��������
always @(posedge clk or posedge reset)
begin
	if(reset)
	begin
		//reset registers and flags
		flag_z_fixed <= 1'b0;
		flag_c_fixed <= 1'b0;
		
		register[0] <= 0;
		register[1] <= 0;
		register[2] <= 0;
		register[3] <= 0;
		
		port0 <= 0;
		port1 <= 0;
	end
	else
	begin
		//fix result only if command not a CP and not BRANCH
		//��������� ������������� ������ ���� ������� �� CP � �� �������
		if( fix_result & (alu_cmd != CMD_CP)  & (opcode[15:12]!=4'b1111) )
		begin
			case(dest_reg_idx)
			0: register[0] <= alu_result;
			1: register[1] <= alu_result;
			2: register[2] <= alu_result;
			3: register[3] <= alu_result;
			4: port0 <= alu_result;
			5: port1 <= alu_result;
			endcase
		end

		//fix alu flags always except BRANCH
		//����� ���������� ������� ��������� ������, ����� ���������
		if( fix_result & (opcode[15:12]!=4'b1111) )
		begin
			flag_z_fixed <= flag_z;
			flag_c_fixed <= flag_c;
		end
	end
end

//���������� ������������� ��������� ��������
wire [1:0]branch_id;
assign branch_id = {opcode[10],opcode[0]};

wire need_jump;
assign need_jump = ( opcode[15:12]==4'b1111 ) & 
				(((branch_id==2'b01) & flag_z_fixed ) |
				( (branch_id==2'b11) & (~flag_z_fixed) ) |
				( (branch_id==2'b00) & flag_c_fixed ) |
				( (branch_id==2'b10) & (~flag_c_fixed) ));

//���������� ���������� �� ��� ������� �� ������ UFM
always @(posedge clk or posedge reset)
begin
	if(reset)
	begin
		ip <= 0;
	end
	else
	begin
		if(arclkshift)
		begin
			//��������������� ��������� �����
			ip <= {ip[7:0],ip[8]};
		end
		else
		if(addr_inc)
		begin
			//go next instruction
			//������� � ��������� ����������
			ip <= ip + 1'b1;
		end
		else
		begin
			//fix instruction pointer
			//jump on condition
			//��������� ��������� ��� �������� ��������
			if( need_jump & opcode_ready )
				ip <= ip + {opcode[9],opcode[9],opcode[9:3]};
		end
	end
end

//UFM (User Flash Memory) reading process
//���������� ���������� ���� �������, ��� � ��� �������� ���������
reg [5:0]ufm_counter;

assign arclkena   = ((ufm_counter<9) | addr_inc) & (~reset);
assign arclkshift = (ufm_counter<9)  & (~reset);
assign ardout = ip[8];
assign drshift    = (ufm_counter>9) & (ufm_counter[4:1]<13) & (~reset);
wire opcode_ready; assign opcode_ready = (ufm_counter[4:1]==13);
wire addr_inc; assign addr_inc = (ufm_counter[3:0]==15);

wire fix_result; assign fix_result = (ufm_counter==10);

//count UFM read states
//������� ����� ��� ������ �� ������ UFM
always @(posedge clk or posedge reset)
begin
	if(reset)
		ufm_counter <= 0;
	else
	begin
		if(opcode_ready)
		begin
			if(need_jump)
				ufm_counter <= 0;
			else
				ufm_counter <= 10;
		end
		else
			ufm_counter <= ufm_counter + 1'b1;
	end
end

//Shift IN data from serial flash of UFM
//��������������� ��������� ��� ���������� �� ������ UFM
always @(posedge clk or posedge reset)
begin
	if(reset)
		opcode <= 0;
	else
	begin
		if(drshift)
			opcode <= {opcode[14:0],drdin};
	end
end

endmodule
