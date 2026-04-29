// ToESampleDlg.h : 標頭檔
//

#pragma once


// CToESampleDlg 對話方塊
class CToESampleDlg : public CDialog
{
// 建構
public:
	CToESampleDlg(CWnd* pParent = NULL);	// 標準建構函式

// 對話方塊資料
	enum { IDD = IDD_TOESAMPLE_DIALOG };

	protected:
	virtual void DoDataExchange(CDataExchange* pDX);	// DDX/DDV 支援



#define	DEVICE_KEY  0x00000001
#define GROUP_KEY1  0x00000001
#define GROUP_KEY2  0x00000002
#define	GROUP_MASK  0xffffffff
#define GROUP_MASK1 0x00000001
#define GROUP_MASK2 0x00000002


// 程式碼實作
protected:
	HICON m_hIcon;
	short m_Number;
	unsigned short m_Port;

	BOOL CheckUserInput();

	// 產生的訊息對應函式
	virtual BOOL OnInitDialog();
	afx_msg void OnSysCommand(UINT nID, LPARAM lParam);
	afx_msg void OnPaint();
	afx_msg HCURSOR OnQueryDragIcon();
	DECLARE_MESSAGE_MAP()
public:
	afx_msg void OnCbnSelchangeComboCardNumber();
public:
	afx_msg void OnBnClickedCheckTriggerEnable();
public:
	void initialDeviceConfig();
	void ActionCommandKey(unsigned short port);

public:
	afx_msg void OnBnClickedOk();
public:
	afx_msg void OnBnClickedRadioRising();
public:
	afx_msg void OnBnClickedRadioFalling();
public:
	afx_msg void OnBnClickedRadioDisable();
public:
	afx_msg void OnBnClickedRadioBoth();
public:
	afx_msg void OnBnClickedRadio4to4();
public:
	afx_msg void OnBnClickedRadio1to4();
public:
	afx_msg void OnBnClickedButtonGet();
public:
	afx_msg void OnBnClickedButtonSet();
public:
	afx_msg void OnCbnSelchangeComboPortNumber();
public:
	afx_msg void OnBnClickedButtonSetAction();
public:
	afx_msg void OnBnClickedButtonStart();
public:
	afx_msg void OnBnClickedButtonPort1Get();
public:
	afx_msg void OnBnClickedButtonPort1Set();
public:
	afx_msg void OnBnClickedButtonPort2Get();
public:
	afx_msg void OnBnClickedButtonPort2Set();
public:
	afx_msg void OnBnClickedButtonPort3Get();
public:
	afx_msg void OnBnClickedButtonPort3Set();
public:
	afx_msg void OnBnClickedButtonPort4Get();
public:
	afx_msg void OnBnClickedButtonPort4Set();
public:
	afx_msg void OnBnClickedButtonCountGet1();
public:
	afx_msg void OnBnClickedButtonCountGet2();
public:
	afx_msg void OnBnClickedButtonCountGet3();
public:
	afx_msg void OnBnClickedButtonCountGet4();
public:
	afx_msg void OnBnClickedButtonReset();
	afx_msg void OnBnClickedRadioSoft();
	afx_msg void OnBnClickedRadioExternal();
	afx_msg void OnBnClickedButton1();
};
