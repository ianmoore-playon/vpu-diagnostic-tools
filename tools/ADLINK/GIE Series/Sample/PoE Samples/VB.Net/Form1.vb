Imports System.Math

Public Class Form1

    Private m_Number As Short = -1

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

    End Sub

    Private Sub Form1_FormClosed(ByVal sender As System.Object, ByVal e As System.Windows.Forms.FormClosedEventArgs) Handles MyBase.FormClosed

        If m_Number >= 0 Then
            SmartPoE.Release_Card(m_Number)
        End If

    End Sub

    Private Sub cboCardNumber_SelectedIndexChanged(ByVal sender As System.Object, ByVal e As System.EventArgs) Handles cboCardNumber.SelectedIndexChanged
        Dim Number As Short
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
End Class
