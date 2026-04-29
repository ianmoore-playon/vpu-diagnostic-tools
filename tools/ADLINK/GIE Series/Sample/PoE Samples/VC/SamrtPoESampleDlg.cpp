// SamrtPoESampleDlg.cpp : implementation file
//

#include "stdafx.h"
#include "SamrtPoESample.h"
#include "SamrtPoESampleDlg.h"
#include "SmartPoE.h"

#ifdef _DEBUG
#define new DEBUG_NEW
#endif


// CSamrtPoESampleDlg dialog




CSamrtPoESampleDlg::CSamrtPoESampleDlg(CWnd* pParent /*=NULL*/)
	: CDialog(CSamrtPoESampleDlg::IDD, pParent),
    m_Number (-1)
{
	m_hIcon = AfxGetApp()->LoadIcon(IDR_MAINFRAME);
}

void CSamrtPoESampleDlg::DoDataExchange(CDataExchange* pDX)
{
	CDialog::DoDataExchange(pDX);
}

BEGIN_MESSAGE_MAP(CSamrtPoESampleDlg, CDialog)
	ON_WM_PAINT()
	ON_WM_QUERYDRAGICON()
	//}}AFX_MSG_MAP
    ON_CBN_SELCHANGE(IDC_COMBO_CARD_NUMBER, &CSamrtPoESampleDlg::OnCbnSelchangeComboCardNumber)
    ON_BN_CLICKED(IDC_BUTTON_SET, &CSamrtPoESampleDlg::OnBnClickedButtonSet)
    ON_WM_DESTROY()
END_MESSAGE_MAP()


// CSamrtPoESampleDlg message handlers

BOOL CSamrtPoESampleDlg::OnInitDialog()
{
	CDialog::OnInitDialog();

	// Set the icon for this dialog.  The framework does this automatically
	//  when the application's main window is not a dialog
	SetIcon(m_hIcon, TRUE);			// Set big icon
	SetIcon(m_hIcon, FALSE);		// Set small icon

    U16 i;
    CString str;
    SHORT num;
    for(i = 0; i < MAX_CARD; i++)
    {
        if((num = SmartPoE_Register_Card(i)) != PoE_NoError)
            break;

        SmartPoE_Release_Card((U16)num);

        str.Format("%d", i);
        ((CComboBox*)GetDlgItem(IDC_COMBO_CARD_NUMBER))->AddString(str);
    }

    if(i == 0)
    {
        MessageBox("No card is found!");
        exit(0);
    }

    ((CComboBox*)GetDlgItem(IDC_COMBO_CARD_NUMBER))->SetCurSel(0);

    OnCbnSelchangeComboCardNumber();

	return TRUE;  // return TRUE  unless you set the focus to a control
}

// If you add a minimize button to your dialog, you will need the code below
//  to draw the icon.  For MFC applications using the document/view model,
//  this is automatically done for you by the framework.

void CSamrtPoESampleDlg::OnPaint()
{
	if (IsIconic())
	{
		CPaintDC dc(this); // device context for painting

		SendMessage(WM_ICONERASEBKGND, reinterpret_cast<WPARAM>(dc.GetSafeHdc()), 0);

		// Center icon in client rectangle
		int cxIcon = GetSystemMetrics(SM_CXICON);
		int cyIcon = GetSystemMetrics(SM_CYICON);
		CRect rect;
		GetClientRect(&rect);
		int x = (rect.Width() - cxIcon + 1) / 2;
		int y = (rect.Height() - cyIcon + 1) / 2;

		// Draw the icon
		dc.DrawIcon(x, y, m_hIcon);
	}
	else
	{
		CDialog::OnPaint();
	}
}

// The system calls this function to obtain the cursor to display while the user drags
//  the minimized window.
HCURSOR CSamrtPoESampleDlg::OnQueryDragIcon()
{
	return static_cast<HCURSOR>(m_hIcon);
}

void CSamrtPoESampleDlg::OnCbnSelchangeComboCardNumber()
{
    I16 Number;
    U16 card_num = (U16)((CComboBox*)GetDlgItem(IDC_COMBO_CARD_NUMBER))->GetCurSel();

    if(m_Number >= 0)
        SmartPoE_Release_Card(m_Number);

    if((Number = SmartPoE_Register_Card(card_num)) != PoE_NoError)
    {
        MessageBox("Selecting card is failed");
        return;
    }

    U16 ID;
    I16 ret = SmartPoE_Get_ID((U16)Number, &ID);
    if(ret < 0)
        SetDlgItemText(IDC_EDIT_ID, "Error");
    else
    {
        char txt[16];
        _itoa_s(ID, txt, sizeof(txt), 10);
        SetDlgItemText(IDC_EDIT_ID, txt);
    }
    
    m_Number = Number;
}

void CSamrtPoESampleDlg::OnDestroy()
{
    CDialog::OnDestroy();

    if(m_Number >= 0)
        SmartPoE_Release_Card(m_Number);
}

void CSamrtPoESampleDlg::OnBnClickedButtonSet()
{
    if(m_Number < 0)
        return;

    if(!CheckUserInput())
    {
        MessageBox("Some ON/OFF state of ports are not set!");
        return;
    }

    U16 EnPort1 = ((CButton*)GetDlgItem(IDC_RADIO_PORT1_ON))->GetCheck() ? 1 : 0;
    U16 EnPort2 = ((CButton*)GetDlgItem(IDC_RADIO_PORT2_ON))->GetCheck() ? 1 : 0;
    U16 EnPort3 = ((CButton*)GetDlgItem(IDC_RADIO_PORT3_ON))->GetCheck() ? 1 : 0;
    U16 EnPort4 = ((CButton*)GetDlgItem(IDC_RADIO_PORT4_ON))->GetCheck() ? 1 : 0;

    if(SmartPoE_Power_Enable(m_Number, EnPort1, EnPort2, EnPort3, EnPort4) != PoE_NoError)
    {
        MessageBox("Setting power is failed");
    }
}

BOOL CSamrtPoESampleDlg::CheckUserInput()
{
    U16 EnPort1On = ((CButton*)GetDlgItem(IDC_RADIO_PORT1_ON))->GetCheck() ? 1 : 0;
    U16 EnPort2On = ((CButton*)GetDlgItem(IDC_RADIO_PORT2_ON))->GetCheck() ? 1 : 0;
    U16 EnPort3On = ((CButton*)GetDlgItem(IDC_RADIO_PORT3_ON))->GetCheck() ? 1 : 0;
    U16 EnPort4On = ((CButton*)GetDlgItem(IDC_RADIO_PORT4_ON))->GetCheck() ? 1 : 0;

    U16 EnPort1Off = ((CButton*)GetDlgItem(IDC_RADIO_PORT1_OFF))->GetCheck() ? 1 : 0;
    U16 EnPort2Off = ((CButton*)GetDlgItem(IDC_RADIO_PORT2_OFF))->GetCheck() ? 1 : 0;
    U16 EnPort3Off = ((CButton*)GetDlgItem(IDC_RADIO_PORT3_OFF))->GetCheck() ? 1 : 0;
    U16 EnPort4Off = ((CButton*)GetDlgItem(IDC_RADIO_PORT4_OFF))->GetCheck() ? 1 : 0;

    if( (!EnPort1On && !EnPort1Off) ||
        (!EnPort2On && !EnPort2Off) ||
        (!EnPort3On && !EnPort3Off) ||
        (!EnPort4On && !EnPort4Off))
        return FALSE;

    return TRUE;
}


