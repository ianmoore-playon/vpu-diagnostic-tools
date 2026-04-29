namespace ToESample
{
    partial class Form1
    {
        /// <summary>
        /// 設計工具所需的變數。
        /// </summary>
        private System.ComponentModel.IContainer components = null;

        /// <summary>
        /// 清除任何使用中的資源。
        /// </summary>
        /// <param name="disposing">如果應該公開 Managed 資源則為 true，否則為 false。</param>
        protected override void Dispose(bool disposing)
        {
            if (disposing && (components != null))
            {
                components.Dispose();
            }
            base.Dispose(disposing);
        }

        #region Windows Form 設計工具產生的程式碼

        /// <summary>
        /// 此為設計工具支援所需的方法 - 請勿使用程式碼編輯器修改這個方法的內容。
        ///
        /// </summary>
        private void InitializeComponent()
        {
            this.label1 = new System.Windows.Forms.Label();
            this.label2 = new System.Windows.Forms.Label();
            this.label3 = new System.Windows.Forms.Label();
            this.label4 = new System.Windows.Forms.Label();
            this.label5 = new System.Windows.Forms.Label();
            this.cboCardNumber = new System.Windows.Forms.ComboBox();
            this.txtCardID = new System.Windows.Forms.TextBox();
            this.panel1 = new System.Windows.Forms.Panel();
            this.rdoOff1 = new System.Windows.Forms.RadioButton();
            this.rdoOn1 = new System.Windows.Forms.RadioButton();
            this.panel2 = new System.Windows.Forms.Panel();
            this.rdoOff2 = new System.Windows.Forms.RadioButton();
            this.rdoOn2 = new System.Windows.Forms.RadioButton();
            this.label6 = new System.Windows.Forms.Label();
            this.panel3 = new System.Windows.Forms.Panel();
            this.rdoOff3 = new System.Windows.Forms.RadioButton();
            this.rdoOn3 = new System.Windows.Forms.RadioButton();
            this.label7 = new System.Windows.Forms.Label();
            this.panel4 = new System.Windows.Forms.Panel();
            this.rdoOff4 = new System.Windows.Forms.RadioButton();
            this.rdoOn4 = new System.Windows.Forms.RadioButton();
            this.label8 = new System.Windows.Forms.Label();
            this.btnSet = new System.Windows.Forms.Button();
            this.groupBox6 = new System.Windows.Forms.GroupBox();
            this.buttonSet = new System.Windows.Forms.Button();
            this.buttonGet = new System.Windows.Forms.Button();
            this.textDebounce = new System.Windows.Forms.TextBox();
            this.groupBoxMode = new System.Windows.Forms.GroupBox();
            this.radioButton1to4 = new System.Windows.Forms.RadioButton();
            this.radioButton4to4 = new System.Windows.Forms.RadioButton();
            this.TriggerActivationgroupBox = new System.Windows.Forms.GroupBox();
            this.radioButtonFalling = new System.Windows.Forms.RadioButton();
            this.radioButtonRising = new System.Windows.Forms.RadioButton();
            this.TriggerStatecheckBox = new System.Windows.Forms.CheckBox();
            this.groupBox4 = new System.Windows.Forms.GroupBox();
            this.groupMaskTextBox = new System.Windows.Forms.TextBox();
            this.label10 = new System.Windows.Forms.Label();
            this.groupKeyTextBox = new System.Windows.Forms.TextBox();
            this.label11 = new System.Windows.Forms.Label();
            this.deviceKeyTextBox = new System.Windows.Forms.TextBox();
            this.label12 = new System.Windows.Forms.Label();
            this.comboBox1 = new System.Windows.Forms.ComboBox();
            this.label9 = new System.Windows.Forms.Label();
            this.ActionCommandbutton = new System.Windows.Forms.Button();
            this.StartTriggerButton = new System.Windows.Forms.Button();
            this.groupBox8 = new System.Windows.Forms.GroupBox();
            this.buttonReset = new System.Windows.Forms.Button();
            this.buttonCounter4 = new System.Windows.Forms.Button();
            this.buttonCounter3 = new System.Windows.Forms.Button();
            this.buttonCounter2 = new System.Windows.Forms.Button();
            this.buttonCounter1 = new System.Windows.Forms.Button();
            this.Port4TriggerCount = new System.Windows.Forms.Label();
            this.Port3TriggerCount = new System.Windows.Forms.Label();
            this.Port2TriggerCount = new System.Windows.Forms.Label();
            this.Port1TriggerCount = new System.Windows.Forms.Label();
            this.groupBox1 = new System.Windows.Forms.GroupBox();
            this.radioButtonSoft = new System.Windows.Forms.RadioButton();
            this.radioButtonExternal = new System.Windows.Forms.RadioButton();
            this.StartAllTriggerButton = new System.Windows.Forms.Button();
            this.groupBoxSoftCMD = new System.Windows.Forms.GroupBox();
            this.panel1.SuspendLayout();
            this.panel2.SuspendLayout();
            this.panel3.SuspendLayout();
            this.panel4.SuspendLayout();
            this.groupBox6.SuspendLayout();
            this.groupBoxMode.SuspendLayout();
            this.TriggerActivationgroupBox.SuspendLayout();
            this.groupBox4.SuspendLayout();
            this.groupBox8.SuspendLayout();
            this.groupBox1.SuspendLayout();
            this.groupBoxSoftCMD.SuspendLayout();
            this.SuspendLayout();
            // 
            // label1
            // 
            this.label1.AutoSize = true;
            this.label1.Location = new System.Drawing.Point(54, 22);
            this.label1.Name = "label1";
            this.label1.Size = new System.Drawing.Size(70, 12);
            this.label1.TabIndex = 0;
            this.label1.Text = "Card number:";
            // 
            // label2
            // 
            this.label2.AutoSize = true;
            this.label2.Location = new System.Drawing.Point(78, 50);
            this.label2.Name = "label2";
            this.label2.Size = new System.Drawing.Size(46, 12);
            this.label2.TabIndex = 1;
            this.label2.Text = "Card ID:";
            // 
            // label3
            // 
            this.label3.AutoSize = true;
            this.label3.Location = new System.Drawing.Point(54, 81);
            this.label3.Name = "label3";
            this.label3.Size = new System.Drawing.Size(24, 12);
            this.label3.TabIndex = 2;
            this.label3.Text = "Port";
            // 
            // label4
            // 
            this.label4.AutoSize = true;
            this.label4.Location = new System.Drawing.Point(98, 81);
            this.label4.Name = "label4";
            this.label4.Size = new System.Drawing.Size(102, 12);
            this.label4.TabIndex = 3;
            this.label4.Text = "Power Over Ethernet";
            // 
            // label5
            // 
            this.label5.AutoSize = true;
            this.label5.Location = new System.Drawing.Point(67, 111);
            this.label5.Name = "label5";
            this.label5.Size = new System.Drawing.Size(11, 12);
            this.label5.TabIndex = 4;
            this.label5.Text = "1";
            // 
            // cboCardNumber
            // 
            this.cboCardNumber.DropDownStyle = System.Windows.Forms.ComboBoxStyle.DropDownList;
            this.cboCardNumber.FormattingEnabled = true;
            this.cboCardNumber.Location = new System.Drawing.Point(130, 19);
            this.cboCardNumber.Name = "cboCardNumber";
            this.cboCardNumber.Size = new System.Drawing.Size(81, 20);
            this.cboCardNumber.TabIndex = 5;
            this.cboCardNumber.SelectedIndexChanged += new System.EventHandler(this.cboCardNumber_SelectedIndexChanged);
            // 
            // txtCardID
            // 
            this.txtCardID.Location = new System.Drawing.Point(130, 45);
            this.txtCardID.Name = "txtCardID";
            this.txtCardID.ReadOnly = true;
            this.txtCardID.Size = new System.Drawing.Size(81, 22);
            this.txtCardID.TabIndex = 6;
            // 
            // panel1
            // 
            this.panel1.Controls.Add(this.rdoOff1);
            this.panel1.Controls.Add(this.rdoOn1);
            this.panel1.Location = new System.Drawing.Point(100, 105);
            this.panel1.Name = "panel1";
            this.panel1.Size = new System.Drawing.Size(111, 23);
            this.panel1.TabIndex = 7;
            // 
            // rdoOff1
            // 
            this.rdoOff1.AutoSize = true;
            this.rdoOff1.Location = new System.Drawing.Point(57, 4);
            this.rdoOff1.Name = "rdoOff1";
            this.rdoOff1.Size = new System.Drawing.Size(43, 16);
            this.rdoOff1.TabIndex = 1;
            this.rdoOff1.TabStop = true;
            this.rdoOff1.Text = "OFF";
            this.rdoOff1.UseVisualStyleBackColor = true;
            // 
            // rdoOn1
            // 
            this.rdoOn1.AutoSize = true;
            this.rdoOn1.Location = new System.Drawing.Point(3, 4);
            this.rdoOn1.Name = "rdoOn1";
            this.rdoOn1.Size = new System.Drawing.Size(39, 16);
            this.rdoOn1.TabIndex = 0;
            this.rdoOn1.TabStop = true;
            this.rdoOn1.Text = "ON";
            this.rdoOn1.UseVisualStyleBackColor = true;
            // 
            // panel2
            // 
            this.panel2.Controls.Add(this.rdoOff2);
            this.panel2.Controls.Add(this.rdoOn2);
            this.panel2.Location = new System.Drawing.Point(100, 133);
            this.panel2.Name = "panel2";
            this.panel2.Size = new System.Drawing.Size(111, 23);
            this.panel2.TabIndex = 9;
            // 
            // rdoOff2
            // 
            this.rdoOff2.AutoSize = true;
            this.rdoOff2.Location = new System.Drawing.Point(57, 4);
            this.rdoOff2.Name = "rdoOff2";
            this.rdoOff2.Size = new System.Drawing.Size(43, 16);
            this.rdoOff2.TabIndex = 1;
            this.rdoOff2.TabStop = true;
            this.rdoOff2.Text = "OFF";
            this.rdoOff2.UseVisualStyleBackColor = true;
            // 
            // rdoOn2
            // 
            this.rdoOn2.AutoSize = true;
            this.rdoOn2.Location = new System.Drawing.Point(3, 4);
            this.rdoOn2.Name = "rdoOn2";
            this.rdoOn2.Size = new System.Drawing.Size(39, 16);
            this.rdoOn2.TabIndex = 0;
            this.rdoOn2.TabStop = true;
            this.rdoOn2.Text = "ON";
            this.rdoOn2.UseVisualStyleBackColor = true;
            // 
            // label6
            // 
            this.label6.AutoSize = true;
            this.label6.Location = new System.Drawing.Point(67, 139);
            this.label6.Name = "label6";
            this.label6.Size = new System.Drawing.Size(11, 12);
            this.label6.TabIndex = 8;
            this.label6.Text = "2";
            // 
            // panel3
            // 
            this.panel3.Controls.Add(this.rdoOff3);
            this.panel3.Controls.Add(this.rdoOn3);
            this.panel3.Location = new System.Drawing.Point(100, 163);
            this.panel3.Name = "panel3";
            this.panel3.Size = new System.Drawing.Size(111, 23);
            this.panel3.TabIndex = 11;
            // 
            // rdoOff3
            // 
            this.rdoOff3.AutoSize = true;
            this.rdoOff3.Location = new System.Drawing.Point(57, 4);
            this.rdoOff3.Name = "rdoOff3";
            this.rdoOff3.Size = new System.Drawing.Size(43, 16);
            this.rdoOff3.TabIndex = 1;
            this.rdoOff3.TabStop = true;
            this.rdoOff3.Text = "OFF";
            this.rdoOff3.UseVisualStyleBackColor = true;
            // 
            // rdoOn3
            // 
            this.rdoOn3.AutoSize = true;
            this.rdoOn3.Location = new System.Drawing.Point(3, 4);
            this.rdoOn3.Name = "rdoOn3";
            this.rdoOn3.Size = new System.Drawing.Size(39, 16);
            this.rdoOn3.TabIndex = 0;
            this.rdoOn3.TabStop = true;
            this.rdoOn3.Text = "ON";
            this.rdoOn3.UseVisualStyleBackColor = true;
            // 
            // label7
            // 
            this.label7.AutoSize = true;
            this.label7.Location = new System.Drawing.Point(67, 169);
            this.label7.Name = "label7";
            this.label7.Size = new System.Drawing.Size(11, 12);
            this.label7.TabIndex = 10;
            this.label7.Text = "3";
            // 
            // panel4
            // 
            this.panel4.Controls.Add(this.rdoOff4);
            this.panel4.Controls.Add(this.rdoOn4);
            this.panel4.Location = new System.Drawing.Point(100, 193);
            this.panel4.Name = "panel4";
            this.panel4.Size = new System.Drawing.Size(111, 23);
            this.panel4.TabIndex = 13;
            // 
            // rdoOff4
            // 
            this.rdoOff4.AutoSize = true;
            this.rdoOff4.Location = new System.Drawing.Point(57, 4);
            this.rdoOff4.Name = "rdoOff4";
            this.rdoOff4.Size = new System.Drawing.Size(43, 16);
            this.rdoOff4.TabIndex = 1;
            this.rdoOff4.TabStop = true;
            this.rdoOff4.Text = "OFF";
            this.rdoOff4.UseVisualStyleBackColor = true;
            // 
            // rdoOn4
            // 
            this.rdoOn4.AutoSize = true;
            this.rdoOn4.Location = new System.Drawing.Point(3, 4);
            this.rdoOn4.Name = "rdoOn4";
            this.rdoOn4.Size = new System.Drawing.Size(39, 16);
            this.rdoOn4.TabIndex = 0;
            this.rdoOn4.TabStop = true;
            this.rdoOn4.Text = "ON";
            this.rdoOn4.UseVisualStyleBackColor = true;
            // 
            // label8
            // 
            this.label8.AutoSize = true;
            this.label8.Location = new System.Drawing.Point(67, 199);
            this.label8.Name = "label8";
            this.label8.Size = new System.Drawing.Size(11, 12);
            this.label8.TabIndex = 12;
            this.label8.Text = "4";
            // 
            // btnSet
            // 
            this.btnSet.Location = new System.Drawing.Point(103, 230);
            this.btnSet.Name = "btnSet";
            this.btnSet.Size = new System.Drawing.Size(75, 23);
            this.btnSet.TabIndex = 14;
            this.btnSet.Text = "&Set";
            this.btnSet.UseVisualStyleBackColor = true;
            this.btnSet.Click += new System.EventHandler(this.btnSet_Click);
            // 
            // groupBox6
            // 
            this.groupBox6.Controls.Add(this.buttonSet);
            this.groupBox6.Controls.Add(this.buttonGet);
            this.groupBox6.Controls.Add(this.textDebounce);
            this.groupBox6.Location = new System.Drawing.Point(251, 276);
            this.groupBox6.Name = "groupBox6";
            this.groupBox6.Size = new System.Drawing.Size(198, 56);
            this.groupBox6.TabIndex = 19;
            this.groupBox6.TabStop = false;
            this.groupBox6.Text = "Trigger Debounce";
            // 
            // buttonSet
            // 
            this.buttonSet.Location = new System.Drawing.Point(153, 20);
            this.buttonSet.Name = "buttonSet";
            this.buttonSet.Size = new System.Drawing.Size(39, 23);
            this.buttonSet.TabIndex = 2;
            this.buttonSet.Text = "Set";
            this.buttonSet.UseVisualStyleBackColor = true;
            this.buttonSet.Click += new System.EventHandler(this.buttonSet_Click);
            // 
            // buttonGet
            // 
            this.buttonGet.Location = new System.Drawing.Point(115, 20);
            this.buttonGet.Name = "buttonGet";
            this.buttonGet.Size = new System.Drawing.Size(39, 23);
            this.buttonGet.TabIndex = 1;
            this.buttonGet.Text = "Get";
            this.buttonGet.UseVisualStyleBackColor = true;
            this.buttonGet.Click += new System.EventHandler(this.buttonGet_Click);
            // 
            // textDebounce
            // 
            this.textDebounce.Location = new System.Drawing.Point(7, 22);
            this.textDebounce.Name = "textDebounce";
            this.textDebounce.Size = new System.Drawing.Size(100, 22);
            this.textDebounce.TabIndex = 0;
            // 
            // groupBoxMode
            // 
            this.groupBoxMode.Controls.Add(this.radioButton1to4);
            this.groupBoxMode.Controls.Add(this.radioButton4to4);
            this.groupBoxMode.Location = new System.Drawing.Point(252, 214);
            this.groupBoxMode.Name = "groupBoxMode";
            this.groupBoxMode.Size = new System.Drawing.Size(187, 56);
            this.groupBoxMode.TabIndex = 17;
            this.groupBoxMode.TabStop = false;
            this.groupBoxMode.Text = "TriggerType";
            // 
            // radioButton1to4
            // 
            this.radioButton1to4.AutoSize = true;
            this.radioButton1to4.Location = new System.Drawing.Point(107, 26);
            this.radioButton1to4.Name = "radioButton1to4";
            this.radioButton1to4.Size = new System.Drawing.Size(50, 16);
            this.radioButton1to4.TabIndex = 1;
            this.radioButton1to4.TabStop = true;
            this.radioButton1to4.Text = "1 to 4";
            this.radioButton1to4.UseVisualStyleBackColor = true;
            this.radioButton1to4.CheckedChanged += new System.EventHandler(this.radioButton1to4_CheckedChanged);
            // 
            // radioButton4to4
            // 
            this.radioButton4to4.AutoSize = true;
            this.radioButton4to4.Location = new System.Drawing.Point(19, 26);
            this.radioButton4to4.Name = "radioButton4to4";
            this.radioButton4to4.Size = new System.Drawing.Size(50, 16);
            this.radioButton4to4.TabIndex = 0;
            this.radioButton4to4.TabStop = true;
            this.radioButton4to4.Text = "4 to 4";
            this.radioButton4to4.UseVisualStyleBackColor = true;
            this.radioButton4to4.CheckedChanged += new System.EventHandler(this.radioButton4to4_CheckedChanged);
            // 
            // TriggerActivationgroupBox
            // 
            this.TriggerActivationgroupBox.Controls.Add(this.radioButtonFalling);
            this.TriggerActivationgroupBox.Controls.Add(this.radioButtonRising);
            this.TriggerActivationgroupBox.Location = new System.Drawing.Point(252, 148);
            this.TriggerActivationgroupBox.Name = "TriggerActivationgroupBox";
            this.TriggerActivationgroupBox.Size = new System.Drawing.Size(187, 60);
            this.TriggerActivationgroupBox.TabIndex = 16;
            this.TriggerActivationgroupBox.TabStop = false;
            this.TriggerActivationgroupBox.Text = "TriggerActivation";
            // 
            // radioButtonFalling
            // 
            this.radioButtonFalling.AutoSize = true;
            this.radioButtonFalling.Location = new System.Drawing.Point(107, 26);
            this.radioButtonFalling.Name = "radioButtonFalling";
            this.radioButtonFalling.Size = new System.Drawing.Size(55, 16);
            this.radioButtonFalling.TabIndex = 1;
            this.radioButtonFalling.TabStop = true;
            this.radioButtonFalling.Text = "Falling";
            this.radioButtonFalling.UseVisualStyleBackColor = true;
            this.radioButtonFalling.CheckedChanged += new System.EventHandler(this.radioButtonFalling_CheckedChanged);
            // 
            // radioButtonRising
            // 
            this.radioButtonRising.AutoSize = true;
            this.radioButtonRising.Location = new System.Drawing.Point(19, 26);
            this.radioButtonRising.Name = "radioButtonRising";
            this.radioButtonRising.Size = new System.Drawing.Size(53, 16);
            this.radioButtonRising.TabIndex = 0;
            this.radioButtonRising.TabStop = true;
            this.radioButtonRising.Text = "Rising";
            this.radioButtonRising.UseVisualStyleBackColor = true;
            this.radioButtonRising.CheckedChanged += new System.EventHandler(this.radioButtonRising_CheckedChanged);
            // 
            // TriggerStatecheckBox
            // 
            this.TriggerStatecheckBox.AutoSize = true;
            this.TriggerStatecheckBox.Location = new System.Drawing.Point(252, 59);
            this.TriggerStatecheckBox.Name = "TriggerStatecheckBox";
            this.TriggerStatecheckBox.Size = new System.Drawing.Size(89, 16);
            this.TriggerStatecheckBox.TabIndex = 15;
            this.TriggerStatecheckBox.Text = "Trigger Mode";
            this.TriggerStatecheckBox.UseVisualStyleBackColor = true;
            this.TriggerStatecheckBox.CheckedChanged += new System.EventHandler(this.TriggerStatecheckBox_CheckedChanged);
            // 
            // groupBox4
            // 
            this.groupBox4.Controls.Add(this.groupMaskTextBox);
            this.groupBox4.Controls.Add(this.label10);
            this.groupBox4.Controls.Add(this.groupKeyTextBox);
            this.groupBox4.Controls.Add(this.label11);
            this.groupBox4.Controls.Add(this.deviceKeyTextBox);
            this.groupBox4.Controls.Add(this.label12);
            this.groupBox4.Controls.Add(this.ActionCommandbutton);
            this.groupBox4.Location = new System.Drawing.Point(458, 111);
            this.groupBox4.Name = "groupBox4";
            this.groupBox4.Size = new System.Drawing.Size(154, 122);
            this.groupBox4.TabIndex = 34;
            this.groupBox4.TabStop = false;
            this.groupBox4.Text = "Action Command Data";
            // 
            // groupMaskTextBox
            // 
            this.groupMaskTextBox.Location = new System.Drawing.Point(76, 62);
            this.groupMaskTextBox.Name = "groupMaskTextBox";
            this.groupMaskTextBox.Size = new System.Drawing.Size(70, 22);
            this.groupMaskTextBox.TabIndex = 4;
            this.groupMaskTextBox.Text = "0x00000001";
            this.groupMaskTextBox.TextAlign = System.Windows.Forms.HorizontalAlignment.Right;
            // 
            // label10
            // 
            this.label10.AutoSize = true;
            this.label10.Location = new System.Drawing.Point(5, 65);
            this.label10.Name = "label10";
            this.label10.Size = new System.Drawing.Size(66, 12);
            this.label10.TabIndex = 4;
            this.label10.Text = "Group Mask:";
            // 
            // groupKeyTextBox
            // 
            this.groupKeyTextBox.Location = new System.Drawing.Point(76, 39);
            this.groupKeyTextBox.Name = "groupKeyTextBox";
            this.groupKeyTextBox.Size = new System.Drawing.Size(70, 22);
            this.groupKeyTextBox.TabIndex = 3;
            this.groupKeyTextBox.Text = "0x00000001";
            this.groupKeyTextBox.TextAlign = System.Windows.Forms.HorizontalAlignment.Right;
            // 
            // label11
            // 
            this.label11.AutoSize = true;
            this.label11.Location = new System.Drawing.Point(5, 42);
            this.label11.Name = "label11";
            this.label11.Size = new System.Drawing.Size(60, 12);
            this.label11.TabIndex = 2;
            this.label11.Text = "Group Key:";
            // 
            // deviceKeyTextBox
            // 
            this.deviceKeyTextBox.Location = new System.Drawing.Point(76, 16);
            this.deviceKeyTextBox.Name = "deviceKeyTextBox";
            this.deviceKeyTextBox.Size = new System.Drawing.Size(70, 22);
            this.deviceKeyTextBox.TabIndex = 2;
            this.deviceKeyTextBox.Text = "0x00000001";
            this.deviceKeyTextBox.TextAlign = System.Windows.Forms.HorizontalAlignment.Right;
            // 
            // label12
            // 
            this.label12.AutoSize = true;
            this.label12.Location = new System.Drawing.Point(5, 18);
            this.label12.Name = "label12";
            this.label12.Size = new System.Drawing.Size(62, 12);
            this.label12.TabIndex = 0;
            this.label12.Text = "Device Key:";
            // 
            // comboBox1
            // 
            this.comboBox1.DropDownStyle = System.Windows.Forms.ComboBoxStyle.DropDownList;
            this.comboBox1.FormattingEnabled = true;
            this.comboBox1.Items.AddRange(new object[] {
            "1",
            "2",
            "3",
            "4"});
            this.comboBox1.Location = new System.Drawing.Point(531, 78);
            this.comboBox1.Name = "comboBox1";
            this.comboBox1.Size = new System.Drawing.Size(81, 20);
            this.comboBox1.TabIndex = 33;
            this.comboBox1.SelectedIndexChanged += new System.EventHandler(this.comboBox1_SelectedIndexChanged);
            // 
            // label9
            // 
            this.label9.AutoSize = true;
            this.label9.Location = new System.Drawing.Point(455, 81);
            this.label9.Name = "label9";
            this.label9.Size = new System.Drawing.Size(66, 12);
            this.label9.TabIndex = 32;
            this.label9.Text = "Port number:";
            // 
            // ActionCommandbutton
            // 
            this.ActionCommandbutton.Location = new System.Drawing.Point(7, 90);
            this.ActionCommandbutton.Name = "ActionCommandbutton";
            this.ActionCommandbutton.Size = new System.Drawing.Size(139, 23);
            this.ActionCommandbutton.TabIndex = 31;
            this.ActionCommandbutton.Text = "SendActionCommand";
            this.ActionCommandbutton.UseVisualStyleBackColor = true;
            this.ActionCommandbutton.Click += new System.EventHandler(this.ActionCommandbutton_Click);
            // 
            // StartTriggerButton
            // 
            this.StartTriggerButton.Location = new System.Drawing.Point(7, 21);
            this.StartTriggerButton.Name = "StartTriggerButton";
            this.StartTriggerButton.Size = new System.Drawing.Size(139, 25);
            this.StartTriggerButton.TabIndex = 35;
            this.StartTriggerButton.Text = "Start Trigger";
            this.StartTriggerButton.TextImageRelation = System.Windows.Forms.TextImageRelation.ImageAboveText;
            this.StartTriggerButton.UseVisualStyleBackColor = true;
            this.StartTriggerButton.Click += new System.EventHandler(this.StartTriggerButton_Click);
            // 
            // groupBox8
            // 
            this.groupBox8.Controls.Add(this.buttonReset);
            this.groupBox8.Controls.Add(this.buttonCounter4);
            this.groupBox8.Controls.Add(this.buttonCounter3);
            this.groupBox8.Controls.Add(this.buttonCounter2);
            this.groupBox8.Controls.Add(this.buttonCounter1);
            this.groupBox8.Controls.Add(this.Port4TriggerCount);
            this.groupBox8.Controls.Add(this.Port3TriggerCount);
            this.groupBox8.Controls.Add(this.Port2TriggerCount);
            this.groupBox8.Controls.Add(this.Port1TriggerCount);
            this.groupBox8.Location = new System.Drawing.Point(622, 79);
            this.groupBox8.Name = "groupBox8";
            this.groupBox8.Size = new System.Drawing.Size(258, 191);
            this.groupBox8.TabIndex = 38;
            this.groupBox8.TabStop = false;
            this.groupBox8.Text = "Trigger Counter ( Trigger in count, ToE out count)";
            // 
            // buttonReset
            // 
            this.buttonReset.Location = new System.Drawing.Point(140, 148);
            this.buttonReset.Name = "buttonReset";
            this.buttonReset.Size = new System.Drawing.Size(102, 26);
            this.buttonReset.TabIndex = 8;
            this.buttonReset.Text = "Reset Counter";
            this.buttonReset.UseVisualStyleBackColor = true;
            this.buttonReset.Click += new System.EventHandler(this.buttonReset_Click);
            // 
            // buttonCounter4
            // 
            this.buttonCounter4.Location = new System.Drawing.Point(140, 115);
            this.buttonCounter4.Name = "buttonCounter4";
            this.buttonCounter4.Size = new System.Drawing.Size(72, 23);
            this.buttonCounter4.TabIndex = 7;
            this.buttonCounter4.Text = "Get#4";
            this.buttonCounter4.UseVisualStyleBackColor = true;
            this.buttonCounter4.Click += new System.EventHandler(this.buttonCounter4_Click);
            // 
            // buttonCounter3
            // 
            this.buttonCounter3.Location = new System.Drawing.Point(140, 84);
            this.buttonCounter3.Name = "buttonCounter3";
            this.buttonCounter3.Size = new System.Drawing.Size(72, 23);
            this.buttonCounter3.TabIndex = 6;
            this.buttonCounter3.Text = "Get#3";
            this.buttonCounter3.UseVisualStyleBackColor = true;
            this.buttonCounter3.Click += new System.EventHandler(this.buttonCounter3_Click);
            // 
            // buttonCounter2
            // 
            this.buttonCounter2.Location = new System.Drawing.Point(140, 53);
            this.buttonCounter2.Name = "buttonCounter2";
            this.buttonCounter2.Size = new System.Drawing.Size(72, 23);
            this.buttonCounter2.TabIndex = 5;
            this.buttonCounter2.Text = "Get#2";
            this.buttonCounter2.UseVisualStyleBackColor = true;
            this.buttonCounter2.Click += new System.EventHandler(this.buttonCounter2_Click);
            // 
            // buttonCounter1
            // 
            this.buttonCounter1.Location = new System.Drawing.Point(140, 21);
            this.buttonCounter1.Name = "buttonCounter1";
            this.buttonCounter1.Size = new System.Drawing.Size(72, 23);
            this.buttonCounter1.TabIndex = 4;
            this.buttonCounter1.Text = "Get#1";
            this.buttonCounter1.UseVisualStyleBackColor = true;
            this.buttonCounter1.Click += new System.EventHandler(this.buttonCounter1_Click);
            // 
            // Port4TriggerCount
            // 
            this.Port4TriggerCount.AutoSize = true;
            this.Port4TriggerCount.Font = new System.Drawing.Font("新細明體", 12F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(136)));
            this.Port4TriggerCount.Location = new System.Drawing.Point(24, 117);
            this.Port4TriggerCount.Name = "Port4TriggerCount";
            this.Port4TriggerCount.Size = new System.Drawing.Size(83, 16);
            this.Port4TriggerCount.TabIndex = 3;
            this.Port4TriggerCount.Text = "(0,0) counts";
            // 
            // Port3TriggerCount
            // 
            this.Port3TriggerCount.AutoSize = true;
            this.Port3TriggerCount.Font = new System.Drawing.Font("新細明體", 12F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(136)));
            this.Port3TriggerCount.Location = new System.Drawing.Point(24, 84);
            this.Port3TriggerCount.Name = "Port3TriggerCount";
            this.Port3TriggerCount.Size = new System.Drawing.Size(83, 16);
            this.Port3TriggerCount.TabIndex = 2;
            this.Port3TriggerCount.Text = "(0,0) counts";
            // 
            // Port2TriggerCount
            // 
            this.Port2TriggerCount.AutoSize = true;
            this.Port2TriggerCount.Font = new System.Drawing.Font("新細明體", 12F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(136)));
            this.Port2TriggerCount.Location = new System.Drawing.Point(24, 53);
            this.Port2TriggerCount.Name = "Port2TriggerCount";
            this.Port2TriggerCount.Size = new System.Drawing.Size(83, 16);
            this.Port2TriggerCount.TabIndex = 1;
            this.Port2TriggerCount.Text = "(0,0) counts";
            // 
            // Port1TriggerCount
            // 
            this.Port1TriggerCount.AutoSize = true;
            this.Port1TriggerCount.Font = new System.Drawing.Font("新細明體", 12F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(136)));
            this.Port1TriggerCount.Location = new System.Drawing.Point(24, 23);
            this.Port1TriggerCount.Name = "Port1TriggerCount";
            this.Port1TriggerCount.Size = new System.Drawing.Size(83, 16);
            this.Port1TriggerCount.TabIndex = 0;
            this.Port1TriggerCount.Text = "(0,0) counts";
            // 
            // groupBox1
            // 
            this.groupBox1.Controls.Add(this.radioButtonExternal);
            this.groupBox1.Controls.Add(this.radioButtonSoft);
            this.groupBox1.Location = new System.Drawing.Point(252, 82);
            this.groupBox1.Name = "groupBox1";
            this.groupBox1.Size = new System.Drawing.Size(187, 59);
            this.groupBox1.TabIndex = 39;
            this.groupBox1.TabStop = false;
            this.groupBox1.Text = "TriggerSource";
            // 
            // radioButtonSoft
            // 
            this.radioButtonSoft.AutoSize = true;
            this.radioButtonSoft.Location = new System.Drawing.Point(19, 29);
            this.radioButtonSoft.Name = "radioButtonSoft";
            this.radioButtonSoft.Size = new System.Drawing.Size(64, 16);
            this.radioButtonSoft.TabIndex = 0;
            this.radioButtonSoft.TabStop = true;
            this.radioButtonSoft.Text = "Software";
            this.radioButtonSoft.UseVisualStyleBackColor = true;
            this.radioButtonSoft.CheckedChanged += new System.EventHandler(this.radioButtonSoft_CheckedChanged);
            // 
            // radioButtonExternal
            // 
            this.radioButtonExternal.AutoSize = true;
            this.radioButtonExternal.Location = new System.Drawing.Point(106, 29);
            this.radioButtonExternal.Name = "radioButtonExternal";
            this.radioButtonExternal.Size = new System.Drawing.Size(62, 16);
            this.radioButtonExternal.TabIndex = 1;
            this.radioButtonExternal.TabStop = true;
            this.radioButtonExternal.Text = "External";
            this.radioButtonExternal.UseVisualStyleBackColor = true;
            this.radioButtonExternal.CheckedChanged += new System.EventHandler(this.radioButtonExternal_CheckedChanged);
            // 
            // StartAllTriggerButton
            // 
            this.StartAllTriggerButton.Location = new System.Drawing.Point(7, 56);
            this.StartAllTriggerButton.Name = "StartAllTriggerButton";
            this.StartAllTriggerButton.Size = new System.Drawing.Size(139, 24);
            this.StartAllTriggerButton.TabIndex = 40;
            this.StartAllTriggerButton.Text = "Start Trigger (All Port)";
            this.StartAllTriggerButton.UseVisualStyleBackColor = true;
            this.StartAllTriggerButton.Click += new System.EventHandler(this.StartAllTriggerButton_Click);
            // 
            // groupBoxSoftCMD
            // 
            this.groupBoxSoftCMD.Controls.Add(this.StartTriggerButton);
            this.groupBoxSoftCMD.Controls.Add(this.StartAllTriggerButton);
            this.groupBoxSoftCMD.Location = new System.Drawing.Point(458, 240);
            this.groupBoxSoftCMD.Name = "groupBoxSoftCMD";
            this.groupBoxSoftCMD.Size = new System.Drawing.Size(154, 92);
            this.groupBoxSoftCMD.TabIndex = 41;
            this.groupBoxSoftCMD.TabStop = false;
            this.groupBoxSoftCMD.Text = "Software Command";
            // 
            // Form1
            // 
            this.AutoScaleDimensions = new System.Drawing.SizeF(6F, 12F);
            this.AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            this.ClientSize = new System.Drawing.Size(892, 344);
            this.Controls.Add(this.groupBoxSoftCMD);
            this.Controls.Add(this.groupBox1);
            this.Controls.Add(this.groupBox8);
            this.Controls.Add(this.groupBox4);
            this.Controls.Add(this.comboBox1);
            this.Controls.Add(this.label9);
            this.Controls.Add(this.groupBox6);
            this.Controls.Add(this.groupBoxMode);
            this.Controls.Add(this.TriggerActivationgroupBox);
            this.Controls.Add(this.TriggerStatecheckBox);
            this.Controls.Add(this.btnSet);
            this.Controls.Add(this.panel4);
            this.Controls.Add(this.label8);
            this.Controls.Add(this.panel3);
            this.Controls.Add(this.label7);
            this.Controls.Add(this.panel2);
            this.Controls.Add(this.label6);
            this.Controls.Add(this.panel1);
            this.Controls.Add(this.txtCardID);
            this.Controls.Add(this.cboCardNumber);
            this.Controls.Add(this.label5);
            this.Controls.Add(this.label4);
            this.Controls.Add(this.label3);
            this.Controls.Add(this.label2);
            this.Controls.Add(this.label1);
            this.Name = "Form1";
            this.Text = "ToE Sample";
            this.FormClosed += new System.Windows.Forms.FormClosedEventHandler(this.Form1_FormClosed);
            this.Load += new System.EventHandler(this.Form1_Load);
            this.panel1.ResumeLayout(false);
            this.panel1.PerformLayout();
            this.panel2.ResumeLayout(false);
            this.panel2.PerformLayout();
            this.panel3.ResumeLayout(false);
            this.panel3.PerformLayout();
            this.panel4.ResumeLayout(false);
            this.panel4.PerformLayout();
            this.groupBox6.ResumeLayout(false);
            this.groupBox6.PerformLayout();
            this.groupBoxMode.ResumeLayout(false);
            this.groupBoxMode.PerformLayout();
            this.TriggerActivationgroupBox.ResumeLayout(false);
            this.TriggerActivationgroupBox.PerformLayout();
            this.groupBox4.ResumeLayout(false);
            this.groupBox4.PerformLayout();
            this.groupBox8.ResumeLayout(false);
            this.groupBox8.PerformLayout();
            this.groupBox1.ResumeLayout(false);
            this.groupBox1.PerformLayout();
            this.groupBoxSoftCMD.ResumeLayout(false);
            this.ResumeLayout(false);
            this.PerformLayout();

        }

        #endregion

        private System.Windows.Forms.Label label1;
        private System.Windows.Forms.Label label2;
        private System.Windows.Forms.Label label3;
        private System.Windows.Forms.Label label4;
        private System.Windows.Forms.Label label5;
        private System.Windows.Forms.ComboBox cboCardNumber;
        private System.Windows.Forms.TextBox txtCardID;
        private System.Windows.Forms.Panel panel1;
        private System.Windows.Forms.RadioButton rdoOff1;
        private System.Windows.Forms.RadioButton rdoOn1;
        private System.Windows.Forms.Panel panel2;
        private System.Windows.Forms.RadioButton rdoOff2;
        private System.Windows.Forms.RadioButton rdoOn2;
        private System.Windows.Forms.Label label6;
        private System.Windows.Forms.Panel panel3;
        private System.Windows.Forms.RadioButton rdoOff3;
        private System.Windows.Forms.RadioButton rdoOn3;
        private System.Windows.Forms.Label label7;
        private System.Windows.Forms.Panel panel4;
        private System.Windows.Forms.RadioButton rdoOff4;
        private System.Windows.Forms.RadioButton rdoOn4;
        private System.Windows.Forms.Label label8;
        private System.Windows.Forms.Button btnSet;
        private System.Windows.Forms.GroupBox groupBox6;
        private System.Windows.Forms.Button buttonSet;
        private System.Windows.Forms.Button buttonGet;
        private System.Windows.Forms.TextBox textDebounce;
        private System.Windows.Forms.GroupBox groupBoxMode;
        private System.Windows.Forms.RadioButton radioButton1to4;
        private System.Windows.Forms.RadioButton radioButton4to4;
        private System.Windows.Forms.GroupBox TriggerActivationgroupBox;
        private System.Windows.Forms.RadioButton radioButtonFalling;
        private System.Windows.Forms.RadioButton radioButtonRising;
        private System.Windows.Forms.CheckBox TriggerStatecheckBox;
        private System.Windows.Forms.GroupBox groupBox4;
        private System.Windows.Forms.TextBox groupMaskTextBox;
        private System.Windows.Forms.Label label10;
        private System.Windows.Forms.TextBox groupKeyTextBox;
        private System.Windows.Forms.Label label11;
        private System.Windows.Forms.TextBox deviceKeyTextBox;
        private System.Windows.Forms.Label label12;
        private System.Windows.Forms.ComboBox comboBox1;
        private System.Windows.Forms.Label label9;
        private System.Windows.Forms.Button ActionCommandbutton;
        private System.Windows.Forms.Button StartTriggerButton;
        private System.Windows.Forms.GroupBox groupBox8;
        private System.Windows.Forms.Button buttonReset;
        private System.Windows.Forms.Button buttonCounter4;
        private System.Windows.Forms.Button buttonCounter3;
        private System.Windows.Forms.Button buttonCounter2;
        private System.Windows.Forms.Button buttonCounter1;
        private System.Windows.Forms.Label Port4TriggerCount;
        private System.Windows.Forms.Label Port3TriggerCount;
        private System.Windows.Forms.Label Port2TriggerCount;
        private System.Windows.Forms.Label Port1TriggerCount;
        private System.Windows.Forms.GroupBox groupBox1;
        private System.Windows.Forms.RadioButton radioButtonExternal;
        private System.Windows.Forms.RadioButton radioButtonSoft;
        private System.Windows.Forms.Button StartAllTriggerButton;
        private System.Windows.Forms.GroupBox groupBoxSoftCMD;
    }
}

