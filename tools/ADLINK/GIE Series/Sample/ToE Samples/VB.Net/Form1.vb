Imports System.Math
Imports System.Threading


Public Class Form1

    Private m_Number As Short = -1
    Private m_port As Short
    Public Shared index As Integer

    Dim myDeviceKey As UInt32 = 1
    Dim myGroupKey As UInt32 = 1
    Dim myGroupMask As UInt32 = 1

    Private Sub Form1_Load(ByVal sender As System.Object, ByVal e As System.EventArgs) Handles MyBase.Load

        Dim i As UShort
        Dim num As Short

        For i = 0 To SmartPoE.MAX_CARD - 1

            num = SmartPoE.Register_Card(i)
            If num <> 0 Then
                Exit For
            End If

            SmartPoE.Release_Card(num)

            cboCardNumber.Items.Add(i.ToString())

        Next

        If i = 0 Then

            MessageBox.Show("No card is found!")
            Close()
            Exit Sub

        End If

        cboCardNumber.SelectedIndex = 0
        comboBox1.SelectedIndex = 0
        initialDeviceConfig()

    End Sub

    Public Sub initialDeviceConfig()

        Dim Activation As UShort = 0
        Dim Mode As UShort
        Dim Source As UShort = 0
        Dim Type As UShort = 0
        Dim Debounce As UInteger = 0
        Dim Port1Status As UShort = 0
        Dim Port2Status As UShort = 0
        Dim Port3Status As UShort = 0
        Dim Port4Status As UShort = 0


        'TriggerStatecheckBox.Checked = Convert.ToBoolean(Mode)

        SmartPoE.GetTriggerMode(m_Number, Mode)
        SmartPoE.GetTriggerSource(m_Number, Source)
        SmartPoE.GetTriggerActivation(m_Number, Activation)
        SmartPoE.GetTriggerType(m_Number, Type)
        SmartPoE.GetTriggerDebounce(m_Number, Debounce)
        SmartPoE.Get_Power_Enable(m_Number, Port1Status, Port2Status, Port3Status, Port4Status)


        Dim port As Integer
        For port = 1 To 4 Step port + 1
            If port = 1 Then
                CheckPoEStatus(rdoOn1, rdoOff1, Port1Status)
            ElseIf port = 2 Then
                CheckPoEStatus(rdoOn2, rdoOff2, Port2Status)
            ElseIf port = 3 Then
                CheckPoEStatus(rdoOn3, rdoOff3, Port3Status)
            ElseIf port = 4 Then
                CheckPoEStatus(rdoOn4, rdoOff4, Port4Status)
            End If
        Next


        If Mode = 0 Then
            TriggerStatecheckBox.Checked = False
        ElseIf Mode = 1 Then
            TriggerStatecheckBox.Checked = True
        End If


        If Source = 0 Then
            radioButtonSoft.Checked = True
        ElseIf Source = 1 Then
            radioButtonExternal.Checked = True
        End If

        '1 :Falling Edge 
        '0 :Rising Edge

        If Activation = 1 Then
            radioButtonFalling.Checked = True
        ElseIf Activation = 0 Then
            radioButtonRising.Checked = True
        End If

        If Type = 0 Then
            radioButton4to4.Checked = True
        Else
            radioButton1to4.Checked = True
        End If

        textDebounce.Text = Debounce.ToString()

    End Sub

    Private Sub CheckPoEStatus(ByVal buttonON As RadioButton, ByVal buttonOFF As RadioButton, ByVal Status As UShort)

        Select Case Status
            Case 0
                buttonON.Checked = False
                buttonOFF.Checked = True

            Case 1
                buttonON.Checked = True
                buttonOFF.Checked = False

        End Select

    End Sub


    Private Sub Form1_FormClosed(ByVal sender As System.Object, ByVal e As System.Windows.Forms.FormClosedEventArgs) Handles MyBase.FormClosed

        If m_Number >= 0 Then
            SmartPoE.Release_Card(m_Number)
        End If

    End Sub

    Private Sub cboCardNumber_SelectedIndexChanged(ByVal sender As System.Object, ByVal e As System.EventArgs) Handles cboCardNumber.SelectedIndexChanged
        Dim Number As UShort
        Dim card_num As UShort = cboCardNumber.SelectedIndex

        If m_Number >= 0 Then
            SmartPoE.Release_Card(m_Number)
        End If

        Number = SmartPoE.Register_Card(card_num)
        If Number <> 0 Then

            MessageBox.Show("Selecting card is failed")
            Exit Sub
        End If

        Dim ID As UShort = 0
        Dim ret As Short = SmartPoE.Get_ID(Number, ID)

        If ret < 0 Then
            txtCardID.Text = "Error"
        Else
            txtCardID.Text = ID.ToString()
        End If

        m_Number = Number

        initialDeviceConfig()

    End Sub

    Private Sub btnSet_Click(ByVal sender As System.Object, ByVal e As System.EventArgs) Handles btnSet.Click

        If m_Number < 0 Then
            Exit Sub
        End If

        If Not CheckUserInput() Then
            MessageBox.Show("Some On/OFF state of ports are not set!")
            Exit Sub
        End If

        Dim EnPort1 As UShort = Abs(CInt(rdoOn1.Checked))
        Dim EnPort2 As UShort = Abs(CInt(rdoOn2.Checked))
        Dim EnPort3 As UShort = Abs(CInt(rdoOn3.Checked))
        Dim EnPort4 As UShort = Abs(CInt(rdoOn4.Checked))

        If SmartPoE.Power_Enable(m_Number, EnPort1, EnPort2, EnPort3, EnPort4) <> 0 Then
            MessageBox.Show("Setting power is failed")
        End If

    End Sub

    Private Function CheckUserInput() As Boolean

        Dim EnPort1On As UShort = Abs(CInt(rdoOn1.Checked))
        Dim EnPort2On As UShort = Abs(CInt(rdoOn2.Checked))
        Dim EnPort3On As UShort = Abs(CInt(rdoOn3.Checked))
        Dim EnPort4On As UShort = Abs(CInt(rdoOn4.Checked))

        Dim EnPort1Off As UShort = Abs(CInt(rdoOff1.Checked))
        Dim EnPort2Off As UShort = Abs(CInt(rdoOff2.Checked))
        Dim EnPort3Off As UShort = Abs(CInt(rdoOff3.Checked))
        Dim EnPort4Off As UShort = Abs(CInt(rdoOff4.Checked))

        If (EnPort1On = 0 And EnPort1Off = 0) Or _
            (EnPort2On = 0 And EnPort2Off = 0) Or _
            (EnPort3On = 0 And EnPort3Off = 0) Or _
            (EnPort4On = 0 And EnPort4Off = 0) Then
            Return False
        End If

        Return True

    End Function

    Private Sub ActionCommandbutton_Click(sender As Object, e As EventArgs) Handles ActionCommandbutton.Click
        Dim ret As Integer


        ' Parse the values from the Text Boxes
        Dim valueString As String = deviceKeyTextBox.Text.ToUpper()

        ' Is this a hex number?
        If valueString.Contains("0X") Then
            valueString = valueString.Substring(valueString.IndexOf("0X") + 2)
            myDeviceKey = UInt32.Parse(valueString, System.Globalization.NumberStyles.HexNumber)
        Else
            Try
                myDeviceKey = UInt32.Parse(valueString)
            Catch ex As Exception
                ' We could not parse the address as decimal.
                System.Diagnostics.Debug.WriteLine(ex.Message)
                myDeviceKey = 0
            End Try
        End If

        deviceKeyTextBox.Text = "0x" + myDeviceKey.ToString("X8")

        valueString = groupKeyTextBox.Text.ToUpper()

        ' Is this a hex number?
        If valueString.Contains("0X") Then
            valueString = valueString.Substring(valueString.IndexOf("0X") + 2)
            myGroupKey = UInt32.Parse(valueString, System.Globalization.NumberStyles.HexNumber)
        Else
            Try
                myGroupKey = UInt32.Parse(valueString)
            Catch ex As Exception
                ' We could not parse the address as decimal.
                System.Diagnostics.Debug.WriteLine(ex.Message)
                myGroupKey = 0
            End Try
        End If

        groupKeyTextBox.Text = "0x" + myGroupKey.ToString("X8")

        valueString = groupMaskTextBox.Text.ToUpper()

        ' Is this a hex number?
        If valueString.Contains("0X") Then
            valueString = valueString.Substring(valueString.IndexOf("0X") + 2)
            myGroupMask = UInt32.Parse(valueString, System.Globalization.NumberStyles.HexNumber)
        Else
            Try
                myGroupMask = UInt32.Parse(valueString)
            Catch ex As Exception
                ' We could not parse the address as decimal.
                System.Diagnostics.Debug.WriteLine(ex.Message)
                myGroupMask = 0
            End Try
        End If

        groupMaskTextBox.Text = "0x" + myGroupMask.ToString("X8")

        'myDeviceKey, myGroupKey, myGroupMask 
        ret = SmartPoE.Set_ActionCommand(m_Number, m_port, myDeviceKey, myGroupKey, myGroupMask)
        Thread.Sleep(50) ' Delay time will be different with the system

        If ret < 0 Then
            MessageBox.Show("Error" + ret.ToString())
        End If
    End Sub

    Private Sub TriggerStatecheckBox_CheckedChanged(sender As Object, e As EventArgs) Handles TriggerStatecheckBox.CheckedChanged

        If TriggerStatecheckBox.Checked = True Then
            groupBox4.Enabled = False
            SmartPoE.SetTriggerMode(m_Number, 1)
        Else
            groupBox4.Enabled = True
            SmartPoE.SetTriggerMode(m_Number, 0)
        End If
    End Sub

    Private Sub radioButtonRising_CheckedChanged(sender As Object, e As EventArgs) Handles radioButtonRising.CheckedChanged

        SmartPoE.SetTriggerActivation(CUShort(m_Number), 0)

    End Sub

    Private Sub radioButtonFalling_CheckedChanged(sender As Object, e As EventArgs) Handles radioButtonFalling.CheckedChanged

        SmartPoE.SetTriggerActivation(CUShort(m_Number), 1)

    End Sub

    Private Sub radioButtonDisable_CheckedChanged(sender As Object, e As EventArgs)

        SmartPoE.SetTriggerActivation(CUShort(m_Number), 0)

    End Sub

    Private Sub radioButtonBoth_CheckedChanged(sender As Object, e As EventArgs)

        SmartPoE.SetTriggerActivation(CUShort(m_Number), 3)

    End Sub

    Private Sub radioButton4to4_CheckedChanged(sender As Object, e As EventArgs) Handles radioButton4to4.CheckedChanged

        SmartPoE.SetTriggerType(CUShort(m_Number), 0)

    End Sub

    Private Sub radioButton1to4_CheckedChanged(sender As Object, e As EventArgs) Handles radioButton1to4.CheckedChanged

        SmartPoE.SetTriggerType(CUShort(m_Number), 1)

    End Sub

    Private Sub buttonGet_Click(sender As Object, e As EventArgs) Handles buttonGet.Click

        Dim Debounce As UInteger

        SmartPoE.GetTriggerDebounce(CUShort(m_Number), Debounce)

        textDebounce.Text = Debounce.ToString()

    End Sub

    Private Sub buttonSet_Click(sender As Object, e As EventArgs) Handles buttonSet.Click

        Dim Debounce As UInteger

        Debounce = Convert.ToUInt32(textDebounce.Text)

        SmartPoE.SetTriggerDebounce(CUShort(m_Number), Debounce)

    End Sub

    Private Sub comboBox1_SelectedIndexChanged(sender As Object, e As EventArgs) Handles comboBox1.SelectedIndexChanged

        index = comboBox1.SelectedIndex

        Select Case index
            Case 0
                m_port = 1
                ActionCommandKey(CUShort(m_port))
            Case 1
                m_port = 2
                ActionCommandKey(CUShort(m_port))
            Case 2
                m_port = 3
                ActionCommandKey(CUShort(m_port))
            Case 3
                m_port = 4
                ActionCommandKey(CUShort(m_port))

        End Select

    End Sub

    Private Sub ActionCommandKey(ByVal port As UShort)

        Dim deviceKey As UInteger
        Dim groupKey As UInteger
        Dim GroupMask As UInteger

        SmartPoE.Get_ActionCommand(CUShort(m_Number), CUShort(port), deviceKey, groupKey, GroupMask)

        deviceKeyTextBox.Text = "0x" + deviceKey.ToString("X8")

        groupKeyTextBox.Text = "0x" + groupKey.ToString("X8")

        groupMaskTextBox.Text = "0x" + GroupMask.ToString("X8")

    End Sub



    Private Sub StartTriggerButton_Click(sender As Object, e As EventArgs) Handles StartTriggerButton.Click

        SmartPoE.Send_SoftwareActionCommand(CUShort(m_Number), CUShort(m_port))

    End Sub


    Private Sub buttonCounter1_Click(sender As Object, e As EventArgs) Handles buttonCounter1.Click


        Dim TriggerCount As UShort
        Dim TriggerSentCount As UShort
        Dim ret As Short
        ret = SmartPoE.GetTriggerCount(CUShort(m_Number), 1, TriggerCount, TriggerSentCount)

        Port1TriggerCount.Text = "(" + TriggerCount.ToString() + "," + TriggerSentCount.ToString() + ") counts"


    End Sub

    Private Sub buttonCounter2_Click(sender As Object, e As EventArgs) Handles buttonCounter2.Click

        Dim TriggerCount As UShort
        Dim TriggerSentCount As UShort
        Dim ret As Short
        ret = SmartPoE.GetTriggerCount(CUShort(m_Number), 2, TriggerCount, TriggerSentCount)

        Port2TriggerCount.Text = "(" + TriggerCount.ToString() + "," + TriggerSentCount.ToString() + ") counts"

    End Sub

    Private Sub buttonCounter3_Click(sender As Object, e As EventArgs) Handles buttonCounter3.Click

        Dim TriggerCount As UShort
        Dim TriggerSentCount As UShort
        Dim ret As Short
        ret = SmartPoE.GetTriggerCount(CUShort(m_Number), 3, TriggerCount, TriggerSentCount)

        Port3TriggerCount.Text = "(" + TriggerCount.ToString() + "," + TriggerSentCount.ToString() + ") counts"

    End Sub

    Private Sub buttonCounter4_Click(sender As Object, e As EventArgs) Handles buttonCounter4.Click

        Dim TriggerCount As UShort
        Dim TriggerSentCount As UShort
        Dim ret As Short
        ret = SmartPoE.GetTriggerCount(CUShort(m_Number), 4, TriggerCount, TriggerSentCount)

        Port4TriggerCount.Text = "(" + TriggerCount.ToString() + "," + TriggerSentCount.ToString() + ") counts"

    End Sub

    Private Sub buttonReset_Click(sender As Object, e As EventArgs) Handles buttonReset.Click

        SmartPoE.ResetTriggerCount(CUShort(m_Number))

    End Sub

    Private Sub radioButtonSoft_CheckedChanged(sender As Object, e As EventArgs) Handles radioButtonSoft.CheckedChanged
        groupBoxSoftCMD.Enabled = True
        SmartPoE.SetTriggerSource(CUShort(m_Number), 0)

    End Sub

    Private Sub radioButtonExternal_CheckedChanged(sender As Object, e As EventArgs) Handles radioButtonExternal.CheckedChanged
        groupBoxSoftCMD.Enabled = False
        SmartPoE.SetTriggerSource(CUShort(m_Number), 1)

    End Sub

    Private Sub StartAllTriggerButton_Click(sender As Object, e As EventArgs) Handles StartAllTriggerButton.Click

        SmartPoE.Send_AllSoftwareActionCommand(CUShort(m_Number))

    End Sub
End Class
