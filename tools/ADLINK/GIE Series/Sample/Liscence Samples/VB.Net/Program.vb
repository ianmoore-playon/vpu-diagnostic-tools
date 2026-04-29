Imports System.Collections.Generic
Imports System.Linq
Imports System.Threading.Tasks
Imports System.Windows.Forms

NotInheritable Class Program
	Private Sub New()
	End Sub
	''' <summary>
	''' 應用程式的主要進入點。
	''' </summary>
	<STAThread> _
	Friend Shared Sub Main()
		Application.EnableVisualStyles()
		Application.SetCompatibleTextRenderingDefault(False)
		Application.Run(New FrmSamrtpoesampleDialog())
	End Sub
End Class
