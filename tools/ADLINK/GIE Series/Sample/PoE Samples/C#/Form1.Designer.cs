namespace SmartPoESample
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
            this.rdoOn1 = new System.Windows.Forms.RadioButton();
            this.rdoOff1 = new System.Windows.Forms.RadioButton();
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
            this.panel1.SuspendLayout();
            this.panel2.SuspendLayout();
            this.panel3.SuspendLayout();
            this.panel4.SuspendLayout();
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
            // Form1
            // 
            this.AutoScaleDimensions = new System.Drawing.SizeF(6F, 12F);
            this.AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            this.ClientSize = new System.Drawing.Size(285, 271);
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
            this.Text = "Smart PoE Sample";
            this.Load += new System.EventHandler(this.Form1_Load);
            this.FormClosed += new System.Windows.Forms.FormClosedEventHandler(this.Form1_FormClosed);
            this.panel1.ResumeLayout(false);
            this.panel1.PerformLayout();
            this.panel2.ResumeLayout(false);
            this.panel2.PerformLayout();
            this.panel3.ResumeLayout(false);
            this.panel3.PerformLayout();
            this.panel4.ResumeLayout(false);
            this.panel4.PerformLayout();
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
    }
}

