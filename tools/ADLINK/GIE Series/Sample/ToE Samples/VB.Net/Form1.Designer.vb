<Global.Microsoft.VisualBasic.CompilerServices.DesignerGenerated()> _
Partial Class Form1
    Inherits System.Windows.Forms.Form

    'Form 覆寫 Dispose 以清除元件清單。
    <System.Diagnostics.DebuggerNonUserCode()> _
    Protected Overrides Sub Dispose(ByVal disposing As Boolean)
        Try
            If disposing AndAlso components IsNot Nothing Then
                components.Dispose()
            End If
        Finally
            MyBase.Dispose(disposing)
        End Try
    End Sub

    '為 Windows Form 設計工具的必要項
    Private components As System.ComponentModel.IContainer

    '注意: 以下為 Windows Form 設計工具所需的程序
    '可以使用 Windows Form 設計工具進行修改。
    '請不要使用程式碼編輯器進行修改。
    <System.Diagnostics.DebuggerStepThrough()> _
    Private Sub InitializeComponent()
        Me.btnSet = New System.Windows.Forms.Button()
        Me.panel4 = New System.Windows.Forms.Panel()
        Me.rdoOff4 = New System.Windows.Forms.RadioButton()
        Me.rdoOn4 = New System.Windows.Forms.RadioButton()
        Me.label8 = New System.Windows.Forms.Label()
        Me.panel3 = New System.Windows.Forms.Panel()
        Me.rdoOff3 = New System.Windows.Forms.RadioButton()
        Me.rdoOn3 = New System.Windows.Forms.RadioButton()
        Me.label7 = New System.Windows.Forms.Label()
        Me.panel2 = New System.Windows.Forms.Panel()
        Me.rdoOff2 = New System.Windows.Forms.RadioButton()
        Me.rdoOn2 = New System.Windows.Forms.RadioButton()
        Me.label6 = New System.Windows.Forms.Label()
        Me.panel1 = New System.Windows.Forms.Panel()
        Me.rdoOff1 = New System.Windows.Forms.RadioButton()
        Me.rdoOn1 = New System.Windows.Forms.RadioButton()
        Me.txtCardID = New System.Windows.Forms.TextBox()
        Me.cboCardNumber = New System.Windows.Forms.ComboBox()
        Me.label5 = New System.Windows.Forms.Label()
        Me.label4 = New System.Windows.Forms.Label()
        Me.label3 = New System.Windows.Forms.Label()
        Me.label2 = New System.Windows.Forms.Label()
        Me.label1 = New System.Windows.Forms.Label()
        Me.groupBox8 = New System.Windows.Forms.GroupBox()
        Me.buttonReset = New System.Windows.Forms.Button()
        Me.buttonCounter4 = New System.Windows.Forms.Button()
        Me.buttonCounter3 = New System.Windows.Forms.Button()
        Me.buttonCounter2 = New System.Windows.Forms.Button()
        Me.buttonCounter1 = New System.Windows.Forms.Button()
        Me.Port4TriggerCount = New System.Windows.Forms.Label()
        Me.Port3TriggerCount = New System.Windows.Forms.Label()
        Me.Port2TriggerCount = New System.Windows.Forms.Label()
        Me.Port1TriggerCount = New System.Windows.Forms.Label()
        Me.StartTriggerButton = New System.Windows.Forms.Button()
        Me.groupBox4 = New System.Windows.Forms.GroupBox()
        Me.groupMaskTextBox = New System.Windows.Forms.TextBox()
        Me.label10 = New System.Windows.Forms.Label()
        Me.groupKeyTextBox = New System.Windows.Forms.TextBox()
        Me.label11 = New System.Windows.Forms.Label()
        Me.deviceKeyTextBox = New System.Windows.Forms.TextBox()
        Me.label12 = New System.Windows.Forms.Label()
        Me.ActionCommandbutton = New System.Windows.Forms.Button()
        Me.comboBox1 = New System.Windows.Forms.ComboBox()
        Me.label9 = New System.Windows.Forms.Label()
        Me.groupBox6 = New System.Windows.Forms.GroupBox()
        Me.buttonSet = New System.Windows.Forms.Button()
        Me.buttonGet = New System.Windows.Forms.Button()
        Me.textDebounce = New System.Windows.Forms.TextBox()
        Me.groupBoxMode = New System.Windows.Forms.GroupBox()
        Me.radioButton1to4 = New System.Windows.Forms.RadioButton()
        Me.radioButton4to4 = New System.Windows.Forms.RadioButton()
        Me.TriggerActivationgroupBox = New System.Windows.Forms.GroupBox()
        Me.radioButtonFalling = New System.Windows.Forms.RadioButton()
        Me.radioButtonRising = New System.Windows.Forms.RadioButton()
        Me.TriggerStatecheckBox = New System.Windows.Forms.CheckBox()
        Me.groupBox1 = New System.Windows.Forms.GroupBox()
        Me.radioButtonExternal = New System.Windows.Forms.RadioButton()
        Me.radioButtonSoft = New System.Windows.Forms.RadioButton()
        Me.groupBoxSoftCMD = New System.Windows.Forms.GroupBox()
        Me.StartAllTriggerButton = New System.Windows.Forms.Button()
        Me.panel4.SuspendLayout()
        Me.panel3.SuspendLayout()
        Me.panel2.SuspendLayout()
        Me.panel1.SuspendLayout()
        Me.groupBox8.SuspendLayout()
        Me.groupBox4.SuspendLayout()
        Me.groupBox6.SuspendLayout()
        Me.groupBoxMode.SuspendLayout()
        Me.TriggerActivationgroupBox.SuspendLayout()
        Me.groupBox1.SuspendLayout()
        Me.groupBoxSoftCMD.SuspendLayout()
        Me.SuspendLayout()
        '
        'btnSet
        '
        Me.btnSet.Location = New System.Drawing.Point(113, 225)
        Me.btnSet.Name = "btnSet"
        Me.btnSet.Size = New System.Drawing.Size(75, 23)
        Me.btnSet.TabIndex = 29
        Me.btnSet.Text = "&Set"
        Me.btnSet.UseVisualStyleBackColor = True
        '
        'panel4
        '
        Me.panel4.Controls.Add(Me.rdoOff4)
        Me.panel4.Controls.Add(Me.rdoOn4)
        Me.panel4.Location = New System.Drawing.Point(110, 188)
        Me.panel4.Name = "panel4"
        Me.panel4.Size = New System.Drawing.Size(111, 23)
        Me.panel4.TabIndex = 28
        '
        'rdoOff4
        '
        Me.rdoOff4.AutoSize = True
        Me.rdoOff4.Location = New System.Drawing.Point(57, 4)
        Me.rdoOff4.Name = "rdoOff4"
        Me.rdoOff4.Size = New System.Drawing.Size(43, 16)
        Me.rdoOff4.TabIndex = 1
        Me.rdoOff4.TabStop = True
        Me.rdoOff4.Text = "OFF"
        Me.rdoOff4.UseVisualStyleBackColor = True
        '
        'rdoOn4
        '
        Me.rdoOn4.AutoSize = True
        Me.rdoOn4.Location = New System.Drawing.Point(3, 4)
        Me.rdoOn4.Name = "rdoOn4"
        Me.rdoOn4.Size = New System.Drawing.Size(39, 16)
        Me.rdoOn4.TabIndex = 0
        Me.rdoOn4.TabStop = True
        Me.rdoOn4.Text = "ON"
        Me.rdoOn4.UseVisualStyleBackColor = True
        '
        'label8
        '
        Me.label8.AutoSize = True
        Me.label8.Location = New System.Drawing.Point(77, 194)
        Me.label8.Name = "label8"
        Me.label8.Size = New System.Drawing.Size(11, 12)
        Me.label8.TabIndex = 27
        Me.label8.Text = "4"
        '
        'panel3
        '
        Me.panel3.Controls.Add(Me.rdoOff3)
        Me.panel3.Controls.Add(Me.rdoOn3)
        Me.panel3.Location = New System.Drawing.Point(110, 158)
        Me.panel3.Name = "panel3"
        Me.panel3.Size = New System.Drawing.Size(111, 23)
        Me.panel3.TabIndex = 26
        '
        'rdoOff3
        '
        Me.rdoOff3.AutoSize = True
        Me.rdoOff3.Location = New System.Drawing.Point(57, 4)
        Me.rdoOff3.Name = "rdoOff3"
        Me.rdoOff3.Size = New System.Drawing.Size(43, 16)
        Me.rdoOff3.TabIndex = 1
        Me.rdoOff3.TabStop = True
        Me.rdoOff3.Text = "OFF"
        Me.rdoOff3.UseVisualStyleBackColor = True
        '
        'rdoOn3
        '
        Me.rdoOn3.AutoSize = True
        Me.rdoOn3.Location = New System.Drawing.Point(3, 4)
        Me.rdoOn3.Name = "rdoOn3"
        Me.rdoOn3.Size = New System.Drawing.Size(39, 16)
        Me.rdoOn3.TabIndex = 0
        Me.rdoOn3.TabStop = True
        Me.rdoOn3.Text = "ON"
        Me.rdoOn3.UseVisualStyleBackColor = True
        '
        'label7
        '
        Me.label7.AutoSize = True
        Me.label7.Location = New System.Drawing.Point(77, 164)
        Me.label7.Name = "label7"
        Me.label7.Size = New System.Drawing.Size(11, 12)
        Me.label7.TabIndex = 25
        Me.label7.Text = "3"
        '
        'panel2
        '
        Me.panel2.Controls.Add(Me.rdoOff2)
        Me.panel2.Controls.Add(Me.rdoOn2)
        Me.panel2.Location = New System.Drawing.Point(110, 128)
        Me.panel2.Name = "panel2"
        Me.panel2.Size = New System.Drawing.Size(111, 23)
        Me.panel2.TabIndex = 24
        '
        'rdoOff2
        '
        Me.rdoOff2.AutoSize = True
        Me.rdoOff2.Location = New System.Drawing.Point(57, 4)
        Me.rdoOff2.Name = "rdoOff2"
        Me.rdoOff2.Size = New System.Drawing.Size(43, 16)
        Me.rdoOff2.TabIndex = 1
        Me.rdoOff2.TabStop = True
        Me.rdoOff2.Text = "OFF"
        Me.rdoOff2.UseVisualStyleBackColor = True
        '
        'rdoOn2
        '
        Me.rdoOn2.AutoSize = True
        Me.rdoOn2.Location = New System.Drawing.Point(3, 4)
        Me.rdoOn2.Name = "rdoOn2"
        Me.rdoOn2.Size = New System.Drawing.Size(39, 16)
        Me.rdoOn2.TabIndex = 0
        Me.rdoOn2.TabStop = True
        Me.rdoOn2.Text = "ON"
        Me.rdoOn2.UseVisualStyleBackColor = True
        '
        'label6
        '
        Me.label6.AutoSize = True
        Me.label6.Location = New System.Drawing.Point(77, 134)
        Me.label6.Name = "label6"
        Me.label6.Size = New System.Drawing.Size(11, 12)
        Me.label6.TabIndex = 23
        Me.label6.Text = "2"
        '
        'panel1
        '
        Me.panel1.Controls.Add(Me.rdoOff1)
        Me.panel1.Controls.Add(Me.rdoOn1)
        Me.panel1.Location = New System.Drawing.Point(110, 100)
        Me.panel1.Name = "panel1"
        Me.panel1.Size = New System.Drawing.Size(111, 23)
        Me.panel1.TabIndex = 22
        '
        'rdoOff1
        '
        Me.rdoOff1.AutoSize = True
        Me.rdoOff1.Location = New System.Drawing.Point(57, 4)
        Me.rdoOff1.Name = "rdoOff1"
        Me.rdoOff1.Size = New System.Drawing.Size(43, 16)
        Me.rdoOff1.TabIndex = 1
        Me.rdoOff1.TabStop = True
        Me.rdoOff1.Text = "OFF"
        Me.rdoOff1.UseVisualStyleBackColor = True
        '
        'rdoOn1
        '
        Me.rdoOn1.AutoSize = True
        Me.rdoOn1.Location = New System.Drawing.Point(3, 4)
        Me.rdoOn1.Name = "rdoOn1"
        Me.rdoOn1.Size = New System.Drawing.Size(39, 16)
        Me.rdoOn1.TabIndex = 0
        Me.rdoOn1.TabStop = True
        Me.rdoOn1.Text = "ON"
        Me.rdoOn1.UseVisualStyleBackColor = True
        '
        'txtCardID
        '
        Me.txtCardID.Location = New System.Drawing.Point(140, 40)
        Me.txtCardID.Name = "txtCardID"
        Me.txtCardID.ReadOnly = True
        Me.txtCardID.Size = New System.Drawing.Size(81, 22)
        Me.txtCardID.TabIndex = 21
        '
        'cboCardNumber
        '
        Me.cboCardNumber.DropDownStyle = System.Windows.Forms.ComboBoxStyle.DropDownList
        Me.cboCardNumber.FormattingEnabled = True
        Me.cboCardNumber.Location = New System.Drawing.Point(140, 14)
        Me.cboCardNumber.Name = "cboCardNumber"
        Me.cboCardNumber.Size = New System.Drawing.Size(81, 20)
        Me.cboCardNumber.TabIndex = 20
        '
        'label5
        '
        Me.label5.AutoSize = True
        Me.label5.Location = New System.Drawing.Point(77, 106)
        Me.label5.Name = "label5"
        Me.label5.Size = New System.Drawing.Size(11, 12)
        Me.label5.TabIndex = 19
        Me.label5.Text = "1"
        '
        'label4
        '
        Me.label4.AutoSize = True
        Me.label4.Location = New System.Drawing.Point(108, 76)
        Me.label4.Name = "label4"
        Me.label4.Size = New System.Drawing.Size(102, 12)
        Me.label4.TabIndex = 18
        Me.label4.Text = "Power Over Ethernet"
        '
        'label3
        '
        Me.label3.AutoSize = True
        Me.label3.Location = New System.Drawing.Point(64, 76)
        Me.label3.Name = "label3"
        Me.label3.Size = New System.Drawing.Size(24, 12)
        Me.label3.TabIndex = 17
        Me.label3.Text = "Port"
        '
        'label2
        '
        Me.label2.AutoSize = True
        Me.label2.Location = New System.Drawing.Point(88, 45)
        Me.label2.Name = "label2"
        Me.label2.Size = New System.Drawing.Size(46, 12)
        Me.label2.TabIndex = 16
        Me.label2.Text = "Card ID:"
        '
        'label1
        '
        Me.label1.AutoSize = True
        Me.label1.Location = New System.Drawing.Point(64, 17)
        Me.label1.Name = "label1"
        Me.label1.Size = New System.Drawing.Size(70, 12)
        Me.label1.TabIndex = 15
        Me.label1.Text = "Card number:"
        '
        'groupBox8
        '
        Me.groupBox8.Controls.Add(Me.buttonReset)
        Me.groupBox8.Controls.Add(Me.buttonCounter4)
        Me.groupBox8.Controls.Add(Me.buttonCounter3)
        Me.groupBox8.Controls.Add(Me.buttonCounter2)
        Me.groupBox8.Controls.Add(Me.buttonCounter1)
        Me.groupBox8.Controls.Add(Me.Port4TriggerCount)
        Me.groupBox8.Controls.Add(Me.Port3TriggerCount)
        Me.groupBox8.Controls.Add(Me.Port2TriggerCount)
        Me.groupBox8.Controls.Add(Me.Port1TriggerCount)
        Me.groupBox8.Location = New System.Drawing.Point(620, 77)
        Me.groupBox8.Name = "groupBox8"
        Me.groupBox8.Size = New System.Drawing.Size(258, 182)
        Me.groupBox8.TabIndex = 49
        Me.groupBox8.TabStop = False
        Me.groupBox8.Text = "Trigger Counter ( Trigger in count, ToE out count)"
        '
        'buttonReset
        '
        Me.buttonReset.Location = New System.Drawing.Point(140, 142)
        Me.buttonReset.Name = "buttonReset"
        Me.buttonReset.Size = New System.Drawing.Size(102, 26)
        Me.buttonReset.TabIndex = 8
        Me.buttonReset.Text = "Reset Counter"
        Me.buttonReset.UseVisualStyleBackColor = True
        '
        'buttonCounter4
        '
        Me.buttonCounter4.Location = New System.Drawing.Point(140, 115)
        Me.buttonCounter4.Name = "buttonCounter4"
        Me.buttonCounter4.Size = New System.Drawing.Size(72, 23)
        Me.buttonCounter4.TabIndex = 7
        Me.buttonCounter4.Text = "Get#4"
        Me.buttonCounter4.UseVisualStyleBackColor = True
        '
        'buttonCounter3
        '
        Me.buttonCounter3.Location = New System.Drawing.Point(140, 84)
        Me.buttonCounter3.Name = "buttonCounter3"
        Me.buttonCounter3.Size = New System.Drawing.Size(72, 23)
        Me.buttonCounter3.TabIndex = 6
        Me.buttonCounter3.Text = "Get#3"
        Me.buttonCounter3.UseVisualStyleBackColor = True
        '
        'buttonCounter2
        '
        Me.buttonCounter2.Location = New System.Drawing.Point(140, 53)
        Me.buttonCounter2.Name = "buttonCounter2"
        Me.buttonCounter2.Size = New System.Drawing.Size(72, 23)
        Me.buttonCounter2.TabIndex = 5
        Me.buttonCounter2.Text = "Get#2"
        Me.buttonCounter2.UseVisualStyleBackColor = True
        '
        'buttonCounter1
        '
        Me.buttonCounter1.Location = New System.Drawing.Point(140, 21)
        Me.buttonCounter1.Name = "buttonCounter1"
        Me.buttonCounter1.Size = New System.Drawing.Size(72, 23)
        Me.buttonCounter1.TabIndex = 4
        Me.buttonCounter1.Text = "Get#1"
        Me.buttonCounter1.UseVisualStyleBackColor = True
        '
        'Port4TriggerCount
        '
        Me.Port4TriggerCount.AutoSize = True
        Me.Port4TriggerCount.Font = New System.Drawing.Font("新細明體", 12.0!, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, CType(136, Byte))
        Me.Port4TriggerCount.Location = New System.Drawing.Point(24, 117)
        Me.Port4TriggerCount.Name = "Port4TriggerCount"
        Me.Port4TriggerCount.Size = New System.Drawing.Size(83, 16)
        Me.Port4TriggerCount.TabIndex = 3
        Me.Port4TriggerCount.Text = "(0,0) counts"
        '
        'Port3TriggerCount
        '
        Me.Port3TriggerCount.AutoSize = True
        Me.Port3TriggerCount.Font = New System.Drawing.Font("新細明體", 12.0!, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, CType(136, Byte))
        Me.Port3TriggerCount.Location = New System.Drawing.Point(24, 84)
        Me.Port3TriggerCount.Name = "Port3TriggerCount"
        Me.Port3TriggerCount.Size = New System.Drawing.Size(83, 16)
        Me.Port3TriggerCount.TabIndex = 2
        Me.Port3TriggerCount.Text = "(0,0) counts"
        '
        'Port2TriggerCount
        '
        Me.Port2TriggerCount.AutoSize = True
        Me.Port2TriggerCount.Font = New System.Drawing.Font("新細明體", 12.0!, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, CType(136, Byte))
        Me.Port2TriggerCount.Location = New System.Drawing.Point(24, 53)
        Me.Port2TriggerCount.Name = "Port2TriggerCount"
        Me.Port2TriggerCount.Size = New System.Drawing.Size(83, 16)
        Me.Port2TriggerCount.TabIndex = 1
        Me.Port2TriggerCount.Text = "(0,0) counts"
        '
        'Port1TriggerCount
        '
        Me.Port1TriggerCount.AutoSize = True
        Me.Port1TriggerCount.Font = New System.Drawing.Font("新細明體", 12.0!, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, CType(136, Byte))
        Me.Port1TriggerCount.Location = New System.Drawing.Point(24, 23)
        Me.Port1TriggerCount.Name = "Port1TriggerCount"
        Me.Port1TriggerCount.Size = New System.Drawing.Size(83, 16)
        Me.Port1TriggerCount.TabIndex = 0
        Me.Port1TriggerCount.Text = "(0,0) counts"
        '
        'StartTriggerButton
        '
        Me.StartTriggerButton.Location = New System.Drawing.Point(11, 20)
        Me.StartTriggerButton.Name = "StartTriggerButton"
        Me.StartTriggerButton.Size = New System.Drawing.Size(139, 26)
        Me.StartTriggerButton.TabIndex = 47
        Me.StartTriggerButton.Text = "Start Trigger"
        Me.StartTriggerButton.TextImageRelation = System.Windows.Forms.TextImageRelation.ImageAboveText
        Me.StartTriggerButton.UseVisualStyleBackColor = True
        '
        'groupBox4
        '
        Me.groupBox4.Controls.Add(Me.groupMaskTextBox)
        Me.groupBox4.Controls.Add(Me.label10)
        Me.groupBox4.Controls.Add(Me.groupKeyTextBox)
        Me.groupBox4.Controls.Add(Me.label11)
        Me.groupBox4.Controls.Add(Me.deviceKeyTextBox)
        Me.groupBox4.Controls.Add(Me.label12)
        Me.groupBox4.Controls.Add(Me.ActionCommandbutton)
        Me.groupBox4.Location = New System.Drawing.Point(456, 110)
        Me.groupBox4.Name = "groupBox4"
        Me.groupBox4.Size = New System.Drawing.Size(154, 121)
        Me.groupBox4.TabIndex = 46
        Me.groupBox4.TabStop = False
        Me.groupBox4.Text = "Action Command Data"
        '
        'groupMaskTextBox
        '
        Me.groupMaskTextBox.Location = New System.Drawing.Point(76, 62)
        Me.groupMaskTextBox.Name = "groupMaskTextBox"
        Me.groupMaskTextBox.Size = New System.Drawing.Size(70, 22)
        Me.groupMaskTextBox.TabIndex = 4
        Me.groupMaskTextBox.Text = "0x00000001"
        Me.groupMaskTextBox.TextAlign = System.Windows.Forms.HorizontalAlignment.Right
        '
        'label10
        '
        Me.label10.AutoSize = True
        Me.label10.Location = New System.Drawing.Point(5, 65)
        Me.label10.Name = "label10"
        Me.label10.Size = New System.Drawing.Size(66, 12)
        Me.label10.TabIndex = 4
        Me.label10.Text = "Group Mask:"
        '
        'groupKeyTextBox
        '
        Me.groupKeyTextBox.Location = New System.Drawing.Point(76, 39)
        Me.groupKeyTextBox.Name = "groupKeyTextBox"
        Me.groupKeyTextBox.Size = New System.Drawing.Size(70, 22)
        Me.groupKeyTextBox.TabIndex = 3
        Me.groupKeyTextBox.Text = "0x00000001"
        Me.groupKeyTextBox.TextAlign = System.Windows.Forms.HorizontalAlignment.Right
        '
        'label11
        '
        Me.label11.AutoSize = True
        Me.label11.Location = New System.Drawing.Point(5, 42)
        Me.label11.Name = "label11"
        Me.label11.Size = New System.Drawing.Size(60, 12)
        Me.label11.TabIndex = 2
        Me.label11.Text = "Group Key:"
        '
        'deviceKeyTextBox
        '
        Me.deviceKeyTextBox.Location = New System.Drawing.Point(76, 16)
        Me.deviceKeyTextBox.Name = "deviceKeyTextBox"
        Me.deviceKeyTextBox.Size = New System.Drawing.Size(70, 22)
        Me.deviceKeyTextBox.TabIndex = 2
        Me.deviceKeyTextBox.Text = "0x00000001"
        Me.deviceKeyTextBox.TextAlign = System.Windows.Forms.HorizontalAlignment.Right
        '
        'label12
        '
        Me.label12.AutoSize = True
        Me.label12.Location = New System.Drawing.Point(5, 18)
        Me.label12.Name = "label12"
        Me.label12.Size = New System.Drawing.Size(62, 12)
        Me.label12.TabIndex = 0
        Me.label12.Text = "Device Key:"
        '
        'ActionCommandbutton
        '
        Me.ActionCommandbutton.Location = New System.Drawing.Point(7, 90)
        Me.ActionCommandbutton.Name = "ActionCommandbutton"
        Me.ActionCommandbutton.Size = New System.Drawing.Size(139, 23)
        Me.ActionCommandbutton.TabIndex = 43
        Me.ActionCommandbutton.Text = "SendActionCommand"
        Me.ActionCommandbutton.UseVisualStyleBackColor = True
        '
        'comboBox1
        '
        Me.comboBox1.DropDownStyle = System.Windows.Forms.ComboBoxStyle.DropDownList
        Me.comboBox1.FormattingEnabled = True
        Me.comboBox1.Items.AddRange(New Object() {"1", "2", "3", "4"})
        Me.comboBox1.Location = New System.Drawing.Point(521, 76)
        Me.comboBox1.Name = "comboBox1"
        Me.comboBox1.Size = New System.Drawing.Size(81, 20)
        Me.comboBox1.TabIndex = 45
        '
        'label9
        '
        Me.label9.AutoSize = True
        Me.label9.Location = New System.Drawing.Point(453, 80)
        Me.label9.Name = "label9"
        Me.label9.Size = New System.Drawing.Size(66, 12)
        Me.label9.TabIndex = 44
        Me.label9.Text = "Port number:"
        '
        'groupBox6
        '
        Me.groupBox6.Controls.Add(Me.buttonSet)
        Me.groupBox6.Controls.Add(Me.buttonGet)
        Me.groupBox6.Controls.Add(Me.textDebounce)
        Me.groupBox6.Location = New System.Drawing.Point(248, 299)
        Me.groupBox6.Name = "groupBox6"
        Me.groupBox6.Size = New System.Drawing.Size(189, 56)
        Me.groupBox6.TabIndex = 42
        Me.groupBox6.TabStop = False
        Me.groupBox6.Text = "Trigger Debounce"
        '
        'buttonSet
        '
        Me.buttonSet.Location = New System.Drawing.Point(139, 20)
        Me.buttonSet.Name = "buttonSet"
        Me.buttonSet.Size = New System.Drawing.Size(39, 23)
        Me.buttonSet.TabIndex = 2
        Me.buttonSet.Text = "Set"
        Me.buttonSet.UseVisualStyleBackColor = True
        '
        'buttonGet
        '
        Me.buttonGet.Location = New System.Drawing.Point(98, 20)
        Me.buttonGet.Name = "buttonGet"
        Me.buttonGet.Size = New System.Drawing.Size(39, 23)
        Me.buttonGet.TabIndex = 1
        Me.buttonGet.Text = "Get"
        Me.buttonGet.UseVisualStyleBackColor = True
        '
        'textDebounce
        '
        Me.textDebounce.Location = New System.Drawing.Point(7, 22)
        Me.textDebounce.Name = "textDebounce"
        Me.textDebounce.Size = New System.Drawing.Size(84, 22)
        Me.textDebounce.TabIndex = 0
        '
        'groupBoxMode
        '
        Me.groupBoxMode.Controls.Add(Me.radioButton1to4)
        Me.groupBoxMode.Controls.Add(Me.radioButton4to4)
        Me.groupBoxMode.Location = New System.Drawing.Point(249, 227)
        Me.groupBoxMode.Name = "groupBoxMode"
        Me.groupBoxMode.Size = New System.Drawing.Size(187, 56)
        Me.groupBoxMode.TabIndex = 41
        Me.groupBoxMode.TabStop = False
        Me.groupBoxMode.Text = "TriggerType"
        '
        'radioButton1to4
        '
        Me.radioButton1to4.AutoSize = True
        Me.radioButton1to4.Location = New System.Drawing.Point(107, 26)
        Me.radioButton1to4.Name = "radioButton1to4"
        Me.radioButton1to4.Size = New System.Drawing.Size(50, 16)
        Me.radioButton1to4.TabIndex = 1
        Me.radioButton1to4.TabStop = True
        Me.radioButton1to4.Text = "1 to 4"
        Me.radioButton1to4.UseVisualStyleBackColor = True
        '
        'radioButton4to4
        '
        Me.radioButton4to4.AutoSize = True
        Me.radioButton4to4.Location = New System.Drawing.Point(19, 26)
        Me.radioButton4to4.Name = "radioButton4to4"
        Me.radioButton4to4.Size = New System.Drawing.Size(50, 16)
        Me.radioButton4to4.TabIndex = 0
        Me.radioButton4to4.TabStop = True
        Me.radioButton4to4.Text = "4 to 4"
        Me.radioButton4to4.UseVisualStyleBackColor = True
        '
        'TriggerActivationgroupBox
        '
        Me.TriggerActivationgroupBox.Controls.Add(Me.radioButtonFalling)
        Me.TriggerActivationgroupBox.Controls.Add(Me.radioButtonRising)
        Me.TriggerActivationgroupBox.Location = New System.Drawing.Point(250, 152)
        Me.TriggerActivationgroupBox.Name = "TriggerActivationgroupBox"
        Me.TriggerActivationgroupBox.Size = New System.Drawing.Size(187, 60)
        Me.TriggerActivationgroupBox.TabIndex = 40
        Me.TriggerActivationgroupBox.TabStop = False
        Me.TriggerActivationgroupBox.Text = "TriggerActivation"
        '
        'radioButtonFalling
        '
        Me.radioButtonFalling.AutoSize = True
        Me.radioButtonFalling.Location = New System.Drawing.Point(107, 26)
        Me.radioButtonFalling.Name = "radioButtonFalling"
        Me.radioButtonFalling.Size = New System.Drawing.Size(55, 16)
        Me.radioButtonFalling.TabIndex = 1
        Me.radioButtonFalling.TabStop = True
        Me.radioButtonFalling.Text = "Falling"
        Me.radioButtonFalling.UseVisualStyleBackColor = True
        '
        'radioButtonRising
        '
        Me.radioButtonRising.AutoSize = True
        Me.radioButtonRising.Location = New System.Drawing.Point(19, 26)
        Me.radioButtonRising.Name = "radioButtonRising"
        Me.radioButtonRising.Size = New System.Drawing.Size(53, 16)
        Me.radioButtonRising.TabIndex = 0
        Me.radioButtonRising.TabStop = True
        Me.radioButtonRising.Text = "Rising"
        Me.radioButtonRising.UseVisualStyleBackColor = True
        '
        'TriggerStatecheckBox
        '
        Me.TriggerStatecheckBox.AutoSize = True
        Me.TriggerStatecheckBox.Location = New System.Drawing.Point(250, 58)
        Me.TriggerStatecheckBox.Name = "TriggerStatecheckBox"
        Me.TriggerStatecheckBox.Size = New System.Drawing.Size(89, 16)
        Me.TriggerStatecheckBox.TabIndex = 39
        Me.TriggerStatecheckBox.Text = "Trigger Mode"
        Me.TriggerStatecheckBox.UseVisualStyleBackColor = True
        '
        'groupBox1
        '
        Me.groupBox1.Controls.Add(Me.radioButtonExternal)
        Me.groupBox1.Controls.Add(Me.radioButtonSoft)
        Me.groupBox1.Location = New System.Drawing.Point(248, 81)
        Me.groupBox1.Name = "groupBox1"
        Me.groupBox1.Size = New System.Drawing.Size(187, 59)
        Me.groupBox1.TabIndex = 50
        Me.groupBox1.TabStop = False
        Me.groupBox1.Text = "TriggerSource"
        '
        'radioButtonExternal
        '
        Me.radioButtonExternal.AutoSize = True
        Me.radioButtonExternal.Location = New System.Drawing.Point(106, 29)
        Me.radioButtonExternal.Name = "radioButtonExternal"
        Me.radioButtonExternal.Size = New System.Drawing.Size(62, 16)
        Me.radioButtonExternal.TabIndex = 1
        Me.radioButtonExternal.TabStop = True
        Me.radioButtonExternal.Text = "External"
        Me.radioButtonExternal.UseVisualStyleBackColor = True
        '
        'radioButtonSoft
        '
        Me.radioButtonSoft.AutoSize = True
        Me.radioButtonSoft.Location = New System.Drawing.Point(19, 29)
        Me.radioButtonSoft.Name = "radioButtonSoft"
        Me.radioButtonSoft.Size = New System.Drawing.Size(64, 16)
        Me.radioButtonSoft.TabIndex = 0
        Me.radioButtonSoft.TabStop = True
        Me.radioButtonSoft.Text = "Software"
        Me.radioButtonSoft.UseVisualStyleBackColor = True
        '
        'groupBoxSoftCMD
        '
        Me.groupBoxSoftCMD.Controls.Add(Me.StartAllTriggerButton)
        Me.groupBoxSoftCMD.Controls.Add(Me.StartTriggerButton)
        Me.groupBoxSoftCMD.Location = New System.Drawing.Point(452, 237)
        Me.groupBoxSoftCMD.Name = "groupBoxSoftCMD"
        Me.groupBoxSoftCMD.Size = New System.Drawing.Size(158, 91)
        Me.groupBoxSoftCMD.TabIndex = 51
        Me.groupBoxSoftCMD.TabStop = False
        Me.groupBoxSoftCMD.Text = "Software Command"
        '
        'StartAllTriggerButton
        '
        Me.StartAllTriggerButton.Location = New System.Drawing.Point(11, 52)
        Me.StartAllTriggerButton.Name = "StartAllTriggerButton"
        Me.StartAllTriggerButton.Size = New System.Drawing.Size(139, 24)
        Me.StartAllTriggerButton.TabIndex = 48
        Me.StartAllTriggerButton.Text = "Start Trigger (All Port)"
        Me.StartAllTriggerButton.UseVisualStyleBackColor = True
        '
        'Form1
        '
        Me.AutoScaleDimensions = New System.Drawing.SizeF(6.0!, 12.0!)
        Me.AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font
        Me.ClientSize = New System.Drawing.Size(890, 376)
        Me.Controls.Add(Me.groupBoxSoftCMD)
        Me.Controls.Add(Me.groupBox1)
        Me.Controls.Add(Me.groupBox8)
        Me.Controls.Add(Me.groupBox4)
        Me.Controls.Add(Me.comboBox1)
        Me.Controls.Add(Me.label9)
        Me.Controls.Add(Me.groupBox6)
        Me.Controls.Add(Me.groupBoxMode)
        Me.Controls.Add(Me.TriggerActivationgroupBox)
        Me.Controls.Add(Me.TriggerStatecheckBox)
        Me.Controls.Add(Me.btnSet)
        Me.Controls.Add(Me.panel4)
        Me.Controls.Add(Me.label8)
        Me.Controls.Add(Me.panel3)
        Me.Controls.Add(Me.label7)
        Me.Controls.Add(Me.panel2)
        Me.Controls.Add(Me.label6)
        Me.Controls.Add(Me.panel1)
        Me.Controls.Add(Me.txtCardID)
        Me.Controls.Add(Me.cboCardNumber)
        Me.Controls.Add(Me.label5)
        Me.Controls.Add(Me.label4)
        Me.Controls.Add(Me.label3)
        Me.Controls.Add(Me.label2)
        Me.Controls.Add(Me.label1)
        Me.Name = "Form1"
        Me.Text = "ToE Sample"
        Me.panel4.ResumeLayout(False)
        Me.panel4.PerformLayout()
        Me.panel3.ResumeLayout(False)
        Me.panel3.PerformLayout()
        Me.panel2.ResumeLayout(False)
        Me.panel2.PerformLayout()
        Me.panel1.ResumeLayout(False)
        Me.panel1.PerformLayout()
        Me.groupBox8.ResumeLayout(False)
        Me.groupBox8.PerformLayout()
        Me.groupBox4.ResumeLayout(False)
        Me.groupBox4.PerformLayout()
        Me.groupBox6.ResumeLayout(False)
        Me.groupBox6.PerformLayout()
        Me.groupBoxMode.ResumeLayout(False)
        Me.groupBoxMode.PerformLayout()
        Me.TriggerActivationgroupBox.ResumeLayout(False)
        Me.TriggerActivationgroupBox.PerformLayout()
        Me.groupBox1.ResumeLayout(False)
        Me.groupBox1.PerformLayout()
        Me.groupBoxSoftCMD.ResumeLayout(False)
        Me.ResumeLayout(False)
        Me.PerformLayout()

    End Sub
    Private WithEvents btnSet As System.Windows.Forms.Button
    Private WithEvents panel4 As System.Windows.Forms.Panel
    Private WithEvents rdoOff4 As System.Windows.Forms.RadioButton
    Private WithEvents rdoOn4 As System.Windows.Forms.RadioButton
    Private WithEvents label8 As System.Windows.Forms.Label
    Private WithEvents panel3 As System.Windows.Forms.Panel
    Private WithEvents rdoOff3 As System.Windows.Forms.RadioButton
    Private WithEvents rdoOn3 As System.Windows.Forms.RadioButton
    Private WithEvents label7 As System.Windows.Forms.Label
    Private WithEvents panel2 As System.Windows.Forms.Panel
    Private WithEvents rdoOff2 As System.Windows.Forms.RadioButton
    Private WithEvents rdoOn2 As System.Windows.Forms.RadioButton
    Private WithEvents label6 As System.Windows.Forms.Label
    Private WithEvents panel1 As System.Windows.Forms.Panel
    Private WithEvents rdoOff1 As System.Windows.Forms.RadioButton
    Private WithEvents rdoOn1 As System.Windows.Forms.RadioButton
    Private WithEvents txtCardID As System.Windows.Forms.TextBox
    Private WithEvents cboCardNumber As System.Windows.Forms.ComboBox
    Private WithEvents label5 As System.Windows.Forms.Label
    Private WithEvents label4 As System.Windows.Forms.Label
    Private WithEvents label3 As System.Windows.Forms.Label
    Private WithEvents label2 As System.Windows.Forms.Label
    Private WithEvents label1 As System.Windows.Forms.Label
    Private WithEvents groupBox8 As System.Windows.Forms.GroupBox
    Private WithEvents buttonReset As System.Windows.Forms.Button
    Private WithEvents buttonCounter4 As System.Windows.Forms.Button
    Private WithEvents buttonCounter3 As System.Windows.Forms.Button
    Private WithEvents buttonCounter2 As System.Windows.Forms.Button
    Private WithEvents buttonCounter1 As System.Windows.Forms.Button
    Private WithEvents Port4TriggerCount As System.Windows.Forms.Label
    Private WithEvents Port3TriggerCount As System.Windows.Forms.Label
    Private WithEvents Port2TriggerCount As System.Windows.Forms.Label
    Private WithEvents Port1TriggerCount As System.Windows.Forms.Label
    Private WithEvents StartTriggerButton As System.Windows.Forms.Button
    Private WithEvents groupBox4 As System.Windows.Forms.GroupBox
    Private WithEvents groupMaskTextBox As System.Windows.Forms.TextBox
    Private WithEvents label10 As System.Windows.Forms.Label
    Private WithEvents groupKeyTextBox As System.Windows.Forms.TextBox
    Private WithEvents label11 As System.Windows.Forms.Label
    Private WithEvents deviceKeyTextBox As System.Windows.Forms.TextBox
    Private WithEvents label12 As System.Windows.Forms.Label
    Private WithEvents comboBox1 As System.Windows.Forms.ComboBox
    Private WithEvents label9 As System.Windows.Forms.Label
    Private WithEvents ActionCommandbutton As System.Windows.Forms.Button
    Private WithEvents groupBox6 As System.Windows.Forms.GroupBox
    Private WithEvents buttonSet As System.Windows.Forms.Button
    Private WithEvents buttonGet As System.Windows.Forms.Button
    Private WithEvents textDebounce As System.Windows.Forms.TextBox
    Private WithEvents groupBoxMode As System.Windows.Forms.GroupBox
    Private WithEvents radioButton1to4 As System.Windows.Forms.RadioButton
    Private WithEvents radioButton4to4 As System.Windows.Forms.RadioButton
    Private WithEvents TriggerActivationgroupBox As System.Windows.Forms.GroupBox
    Private WithEvents radioButtonFalling As System.Windows.Forms.RadioButton
    Private WithEvents radioButtonRising As System.Windows.Forms.RadioButton
    Private WithEvents TriggerStatecheckBox As System.Windows.Forms.CheckBox
    Private WithEvents groupBox1 As System.Windows.Forms.GroupBox
    Private WithEvents radioButtonExternal As System.Windows.Forms.RadioButton
    Private WithEvents radioButtonSoft As System.Windows.Forms.RadioButton
    Friend WithEvents groupBoxSoftCMD As System.Windows.Forms.GroupBox
    Private WithEvents StartAllTriggerButton As System.Windows.Forms.Button

End Class
