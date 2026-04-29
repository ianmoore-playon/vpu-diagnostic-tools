// ToESampleDlg.cpp : 
//

#include "stdafx.h"
#include "ToESample.h"
#include "ToESampleDlg.h"
#include "SmartPoE.h"
#include <windows.h> 

#ifdef _DEBUG
#define new DEBUG_NEW
#endif



class CAboutDlg : public CDialog
{
public:
	CAboutDlg();


	enum { IDD = IDD_ABOUTBOX };

	protected:
	virtual void DoDataExchange(CDataExchange* pDX); 


protected:
	DECLARE_MESSAGE_MAP()
};

CAboutDlg::CAboutDlg() : CDialog(CAboutDlg::IDD)
{
}

void CAboutDlg::DoDataExchange(CDataExchange* pDX)
{
	CDialog::DoDataExchange(pDX);
}

BEGIN_MESSAGE_MAP(CAboutDlg, CDialog)
END_MESSAGE_MAP()


// CToESampleDlg 對話方塊




CToESampleDlg::CToESampleDlg(CWnd* pParent /*=NULL*/)
	: CDialog(CToESampleDlg::IDD, pParent)
{
	m_hIcon = AfxGetApp()->LoadIcon(IDR_MAINFRAME);
}

void CToESampleDlg::DoDataExchange(CDataExchange* pDX)
{
	CDialog::DoDataExchange(pDX);
}

BEGIN_MESSAGE_MAP(CToESampleDlg, CDialog)
	ON_WM_SYSCOMMAND()
	ON_WM_PAINT()
	ON_WM_QUERYDRAGICON()
	//}}AFX_MSG_MAP
	//ON_CBN_SELCHANGE(IDC_COMBO1, &CToESampleDlg::OnCbnSelchangeCombo1)
	ON_CBN_SELCHANGE(IDC_COMBO_CARD_NUMBER, &CToESampleDlg::OnCbnSelchangeComboCardNumber)
	ON_BN_CLICKED(IDC_CHECK_TRIGGER_ENABLE, &CToESampleDlg::OnBnClickedCheckTriggerEnable)
	ON_BN_CLICKED(IDOK, &CToESampleDlg::OnBnClickedOk)
	ON_BN_CLICKED(IDC_RADIO_RISING, &CToESampleDlg::OnBnClickedRadioRising)
	ON_BN_CLICKED(IDC_RADIO_FALLING, &CToESampleDlg::OnBnClickedRadioFalling)

	ON_BN_CLICKED(IDC_RADIO_4TO4, &CToESampleDlg::OnBnClickedRadio4to4)
	ON_BN_CLICKED(IDC_RADIO_1TO4, &CToESampleDlg::OnBnClickedRadio1to4)
	ON_BN_CLICKED(IDC_BUTTON_GET, &CToESampleDlg::OnBnClickedButtonGet)
	ON_BN_CLICKED(IDC_BUTTON_SET, &CToESampleDlg::OnBnClickedButtonSet)
	ON_CBN_SELCHANGE(IDC_COMBO_PORT_NUMBER, &CToESampleDlg::OnCbnSelchangeComboPortNumber)
	ON_BN_CLICKED(IDC_BUTTON_SET_ACTION, &CToESampleDlg::OnBnClickedButtonSetAction)
	ON_BN_CLICKED(IDC_BUTTON_START, &CToESampleDlg::OnBnClickedButtonStart)
	//ON_BN_CLICKED(IDC_BUTTON_PORT1_GET, &CToESampleDlg::OnBnClickedButtonPort1Get)
	//ON_BN_CLICKED(IDC_BUTTON_PORT1_SET, &CToESampleDlg::OnBnClickedButtonPort1Set)
	//ON_BN_CLICKED(IDC_BUTTON_PORT2_GET, &CToESampleDlg::OnBnClickedButtonPort2Get)
	//ON_BN_CLICKED(IDC_BUTTON_PORT2_SET, &CToESampleDlg::OnBnClickedButtonPort2Set)
	//ON_BN_CLICKED(IDC_BUTTON_PORT3_GET, &CToESampleDlg::OnBnClickedButtonPort3Get)
	//ON_BN_CLICKED(IDC_BUTTON_PORT3_SET, &CToESampleDlg::OnBnClickedButtonPort3Set)
	//ON_BN_CLICKED(IDC_BUTTON_PORT4_GET, &CToESampleDlg::OnBnClickedButtonPort4Get)
	//ON_BN_CLICKED(IDC_BUTTON_PORT4_SET, &CToESampleDlg::OnBnClickedButtonPort4Set)
	ON_BN_CLICKED(IDC_BUTTON_COUNT_GET1, &CToESampleDlg::OnBnClickedButtonCountGet1)
	ON_BN_CLICKED(IDC_BUTTON_COUNT_GET2, &CToESampleDlg::OnBnClickedButtonCountGet2)
	ON_BN_CLICKED(IDC_BUTTON_COUNT_GET3, &CToESampleDlg::OnBnClickedButtonCountGet3)
	ON_BN_CLICKED(IDC_BUTTON_COUNT_GET4, &CToESampleDlg::OnBnClickedButtonCountGet4)
	ON_BN_CLICKED(IDC_BUTTON_RESET, &CToESampleDlg::OnBnClickedButtonReset)
	ON_BN_CLICKED(IDC_RADIO_SOFT, &CToESampleDlg::OnBnClickedRadioSoft)
	ON_BN_CLICKED(IDC_RADIO_EXTERNAL, &CToESampleDlg::OnBnClickedRadioExternal)
	ON_BN_CLICKED(IDC_BUTTON1, &CToESampleDlg::OnBnClickedButton1)
END_MESSAGE_MAP()


// CToESampleDlg 訊息處理常式




BOOL CToESampleDlg::OnInitDialog()
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
	initialDeviceConfig();
	OnCbnSelchangeComboPortNumber();

	return TRUE;  // return TRUE  unless you set the focus to a control
}

void CToESampleDlg::initialDeviceConfig()
{
    TCHAR str[256];
	CButton* pButton;

	U16 Type, Activation, Mode, Source;
	U16 Port1Status, Port2Status, Port3Status, Port4Status;
	UINT Debounce;

	GIE_GetTriggerMode(m_Number, &Mode);
	GIE_GetTriggerSource(m_Number, &Source);
    GIE_GetTriggerActivation(m_Number, &Activation);
	GIE_GetTriggerType(m_Number, &Type);
    GIE_GetTriggerDebounce(m_Number, &Debounce);


	if(Mode == 0)
	{
			GetDlgItem(IDC_EDIT_DEVICE_KEY)->EnableWindow(TRUE);
			GetDlgItem(IDC_EDIT_GROUP_KEY)->EnableWindow(TRUE);
			GetDlgItem(IDC_EDIT_GROUP_MASK)->EnableWindow(TRUE);
			GetDlgItem(IDC_BUTTON_SET_ACTION)->EnableWindow(TRUE);//IDC_BUTTON_SET_ACTION
	}
	else
	{
			GetDlgItem(IDC_EDIT_DEVICE_KEY)->EnableWindow(FALSE);
			GetDlgItem(IDC_EDIT_GROUP_KEY)->EnableWindow(FALSE);
			GetDlgItem(IDC_EDIT_GROUP_MASK)->EnableWindow(FALSE);
			GetDlgItem(IDC_BUTTON_SET_ACTION)->EnableWindow(FALSE);//IDC_BUTTON_SET_ACTION
	}


    //Check the POE status 
	SmartPoE_Get_Power_Enable(m_Number, &Port1Status, &Port2Status, &Port3Status, &Port4Status);

	CheckRadioButton(IDC_RADIO_PORT1_ON, IDC_RADIO_PORT1_OFF, IDC_RADIO_PORT1_OFF - Port1Status);
	CheckRadioButton(IDC_RADIO_PORT2_ON, IDC_RADIO_PORT2_OFF, IDC_RADIO_PORT2_OFF - Port2Status);
	CheckRadioButton(IDC_RADIO_PORT3_ON, IDC_RADIO_PORT3_OFF, IDC_RADIO_PORT3_OFF - Port3Status);
	CheckRadioButton(IDC_RADIO_PORT4_ON, IDC_RADIO_PORT4_OFF, IDC_RADIO_PORT4_OFF - Port4Status);


	//0: Software
	//1: External
	CheckRadioButton(IDC_RADIO_SOFT, IDC_RADIO_EXTERNAL , IDC_RADIO_SOFT + Source);

	if(Source == 0)//IDC_BUTTON_START, IDC_BUTTON1
	{
		GetDlgItem(IDC_BUTTON_START)->EnableWindow(TRUE);
		GetDlgItem(IDC_BUTTON1)->EnableWindow(TRUE);
	}
	else
	{
		GetDlgItem(IDC_BUTTON_START)->EnableWindow(FALSE);
		GetDlgItem(IDC_BUTTON1)->EnableWindow(FALSE);
	}


    //1 :Falling Edge 
    //0 :Rising Edge

	CheckRadioButton(IDC_RADIO_RISING, IDC_RADIO_FALLING, IDC_RADIO_RISING + Activation);

	CheckRadioButton(IDC_RADIO_4TO4, IDC_RADIO_1TO4, IDC_RADIO_4TO4 + Type);

    ((CComboBox*)GetDlgItem(IDC_COMBO_PORT_NUMBER))->SetCurSel(0);

	CComboBox *cbo = (CComboBox *)GetDlgItem(IDC_COMBO_PORT_NUMBER);
	m_Port = (cbo->GetCurSel())+1;

	pButton = (CButton*)GetDlgItem(IDC_CHECK_TRIGGER_ENABLE);
	pButton->SetCheck(Mode);


	//LPCTSTR lp;
	//CString str;
	//str.Format("%d",DEVICE_KEY);
	//lp = str;

	sprintf(str, "%u", Debounce);
	SetDlgItemText(IDC_EDIT_DEBOUNCE, str);
	//SetDlgItemText(IDC_EDIT_DEVICE_KEY, "0x00000001");  //"0x00000001"
	//SetDlgItemText(IDC_EDIT_GROUP_KEY, "0x00000001");
	//SetDlgItemText(IDC_EDIT_GROUP_MASK, "0x00000001");

}


void CToESampleDlg::OnSysCommand(UINT nID, LPARAM lParam)
{
	if ((nID & 0xFFF0) == IDM_ABOUTBOX)
	{
		CAboutDlg dlgAbout;
		dlgAbout.DoModal();
	}
	else
	{
		CDialog::OnSysCommand(nID, lParam);
	}
}



void CToESampleDlg::OnPaint()
{
	if (IsIconic())
	{
		CPaintDC dc(this); 

		SendMessage(WM_ICONERASEBKGND, reinterpret_cast<WPARAM>(dc.GetSafeHdc()), 0);

		int cxIcon = GetSystemMetrics(SM_CXICON);
		int cyIcon = GetSystemMetrics(SM_CYICON);
		CRect rect;
		GetClientRect(&rect);
		int x = (rect.Width() - cxIcon + 1) / 2;
		int y = (rect.Height() - cyIcon + 1) / 2;

		dc.DrawIcon(x, y, m_hIcon);
	}
	else
	{
		CDialog::OnPaint();
	}
}

HCURSOR CToESampleDlg::OnQueryDragIcon()
{
	return static_cast<HCURSOR>(m_hIcon);
}


void CToESampleDlg::OnCbnSelchangeComboCardNumber()
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

	initialDeviceConfig();
	//ActionCommandKey((unsigned short)1);
}

void CToESampleDlg::OnBnClickedCheckTriggerEnable()
{
	CButton* pButton;
	int mode;

    pButton = (CButton*)GetDlgItem(IDC_CHECK_TRIGGER_ENABLE);
    mode = pButton->GetCheck();

	if(mode == 0)
	{
			GetDlgItem(IDC_EDIT_DEVICE_KEY)->EnableWindow(TRUE);
			GetDlgItem(IDC_EDIT_GROUP_KEY)->EnableWindow(TRUE);
			GetDlgItem(IDC_EDIT_GROUP_MASK)->EnableWindow(TRUE);
			GetDlgItem(IDC_BUTTON_SET_ACTION)->EnableWindow(TRUE);//IDC_BUTTON_SET_ACTION
	}
	else
	{
			GetDlgItem(IDC_EDIT_DEVICE_KEY)->EnableWindow(FALSE);
			GetDlgItem(IDC_EDIT_GROUP_KEY)->EnableWindow(FALSE);
			GetDlgItem(IDC_EDIT_GROUP_MASK)->EnableWindow(FALSE);
			GetDlgItem(IDC_BUTTON_SET_ACTION)->EnableWindow(FALSE);//IDC_BUTTON_SET_ACTION
	}

    int ret = GIE_SetTriggerMode(m_Number, mode);
}

void CToESampleDlg::OnBnClickedOk()
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

BOOL CToESampleDlg::CheckUserInput()
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



//1 :Falling Edge 
//0 :Rising Edge

void CToESampleDlg::OnBnClickedRadioRising()
{
	GIE_SetTriggerActivation(m_Number, 0);
}

void CToESampleDlg::OnBnClickedRadioFalling()
{
	GIE_SetTriggerActivation(m_Number, 1);
}

void CToESampleDlg::OnBnClickedRadio4to4()
{
	GIE_SetTriggerType(m_Number, 0);
}

void CToESampleDlg::OnBnClickedRadio1to4()
{
	GIE_SetTriggerType(m_Number, 1);
}

void CToESampleDlg::OnBnClickedButtonGet()
{
	int ret;
	TCHAR str[256];
	UINT Debounce;

	// Debounce 
	ret=GIE_GetTriggerDebounce(m_Number, &Debounce);

	sprintf(str, "%u", Debounce);
	SetDlgItemText(IDC_EDIT_DEBOUNCE, str);

}

void CToESampleDlg::OnBnClickedButtonSet()
{
	int ret;
	TCHAR str[256];
	UINT Debounce;

	// Debounce
	GetDlgItemText(IDC_EDIT_DEBOUNCE, str, 255);
	Debounce = (UINT)_strtoui64(str, NULL, 10);
	if(FAILED(ret = GIE_SetTriggerDebounce(m_Number, Debounce)))
	{
		MessageBox("error");
	}
}

void CToESampleDlg::OnCbnSelchangeComboPortNumber()
{

	TCHAR str[256];
	CComboBox *cbo = (CComboBox *)GetDlgItem(IDC_COMBO_PORT_NUMBER);
	m_Port = (cbo->GetCurSel()) + 1;

	ActionCommandKey((unsigned short)m_Port);

	sprintf(str, "%u", m_Port);
	//MessageBox(str);
}

void CToESampleDlg::ActionCommandKey(unsigned short port)
{
	U32 gActionDeviceKey, gActionGroupKey, gActionGroupMask;

	int ret;
	TCHAR str[256];

	ret = GIE_Get_ActionCommand(m_Number, port, &gActionDeviceKey, &gActionGroupKey, &gActionGroupMask);
	//src.ToString("X")
	if(ret<0)
	{
		MessageBox("error");
	}
	// DeiveKey
	
	int iNum = 256;
	CString strHexDeviceKey, strHexGroupKey, strHexGroupMask;
	strHexDeviceKey.Format(_T("0x%08X"), gActionDeviceKey);
	strHexGroupKey.Format(_T("0x%08X"), gActionGroupKey);
	strHexGroupMask.Format(_T("0x%08X"), gActionGroupMask);

	//strHex.Format(_T("%x"), gActionDeviceKey);

	sprintf(str, "%X", gActionDeviceKey);
	SetDlgItemText(IDC_EDIT_DEVICE_KEY, strHexDeviceKey);

	// GruopKey
	sprintf(str, "%u", gActionGroupKey);
	SetDlgItemText(IDC_EDIT_GROUP_KEY, strHexGroupKey);

	// GroupMask
	sprintf(str, "%u", gActionGroupMask);
	SetDlgItemText(IDC_EDIT_GROUP_MASK, strHexGroupMask);

}


void CToESampleDlg::OnBnClickedButtonSetAction()
{
	int ret;
	TCHAR str[256];
	U32 DeiveKey,GruopKey, GroupMask ;

	// DeiveKey
	GetDlgItemText(IDC_EDIT_DEVICE_KEY, str, 255);
	DeiveKey = (U32)_strtoui64(str, NULL, 16);

	// GruopKey
	GetDlgItemText(IDC_EDIT_GROUP_KEY, str, 255);
	GruopKey = (U32)_strtoui64(str, NULL, 16);

	// GroupMask
	GetDlgItemText(IDC_EDIT_GROUP_MASK, str, 255);
	GroupMask = (U32)_strtoui64(str, NULL, 16);


#if 0
	ret = GIE_Set_ActionCommand(m_Number, m_Port, DEVICE_KEY, GROUP_KEY1, GROUP_MASK1);
#endif
	

	ret = GIE_Set_ActionCommand(m_Number, m_Port, DeiveKey, GruopKey, GroupMask);
	Sleep(50); //// Delay time will be different with the system

	if(ret<0)
	{
		MessageBox("error");
	}
}

void CToESampleDlg::OnBnClickedButtonStart()
{
    int ret;

	ret = GIE_Send_SoftwareActionCommand(m_Number, m_Port);

	if(ret<0)
	{
		MessageBox("error");
	}
}



void CToESampleDlg::OnBnClickedButtonCountGet1()
{
	int ret;

    U16 TriggerCount, TriggerSentCount;

	ret = GIE_GetTriggerCount(m_Number, 1, &TriggerCount, & TriggerSentCount);

	if(ret <0)
	{
		//MessageBox("error");
	}

	CString info;
	info.Format("(%d,%d) counts", TriggerCount, TriggerSentCount);

	SetDlgItemText(IDC_STATIC_TRIGGER_COUNT1, info);

}

void CToESampleDlg::OnBnClickedButtonCountGet2()
{
	int ret;

	U16 TriggerCount, TriggerSentCount;

	ret = GIE_GetTriggerCount(m_Number, 2, &TriggerCount, & TriggerSentCount);

	if(ret <0)
	{
		//MessageBox("error");
	}

	CString info;
	info.Format("(%d,%d) counts", TriggerCount, TriggerSentCount);

	SetDlgItemText(IDC_STATIC_TRIGGER_COUNT2, info);
}

void CToESampleDlg::OnBnClickedButtonCountGet3()
{
	int ret;

	U16 TriggerCount = 0, TriggerSentCount = 0;

	ret = GIE_GetTriggerCount(m_Number, 3, &TriggerCount, & TriggerSentCount);

	if(ret <0)
	{
		//MessageBox("error");
	}

	CString info;
	info.Format("(%d,%d) counts", TriggerCount, TriggerSentCount);

	SetDlgItemText(IDC_STATIC_TRIGGER_COUNT3, info);
}

void CToESampleDlg::OnBnClickedButtonCountGet4()
{
	int ret;

	U16 TriggerCount = 0, TriggerSentCount = 0;

	ret = GIE_GetTriggerCount(m_Number, 4, &TriggerCount, & TriggerSentCount);

	if(ret <0)
	{
		//MessageBox("error");
	}

	CString info;
	info.Format("(%d,%d) counts", TriggerCount, TriggerSentCount);

	SetDlgItemText(IDC_STATIC_TRIGGER_COUNT4, info);
}

void CToESampleDlg::OnBnClickedButtonReset()
{
    int ret;

	ret = GIE_ResetTriggerCount(m_Number);

	if(ret<0)
	{
		MessageBox("error");
	}
}


void CToESampleDlg::OnBnClickedRadioSoft()
{
	GIE_SetTriggerSource(m_Number, 0);

	GetDlgItem(IDC_BUTTON_START)->EnableWindow(TRUE);
	GetDlgItem(IDC_BUTTON1)->EnableWindow(TRUE);
}


void CToESampleDlg::OnBnClickedRadioExternal()
{
	GIE_SetTriggerSource(m_Number, 1);

	GetDlgItem(IDC_BUTTON_START)->EnableWindow(FALSE);
	GetDlgItem(IDC_BUTTON1)->EnableWindow(FALSE);
}


void CToESampleDlg::OnBnClickedButton1()
{
	GIE_Send_AllSoftwareActionCommand(m_Number);
}
