// SamrtPoESampleDlg.h : header file
//

#pragma once


// CSamrtPoESampleDlg dialog
class CSamrtPoESampleDlg : public CDialog
{
// Construction
public:
	CSamrtPoESampleDlg(CWnd* pParent = NULL);	// standard constructor

// Dialog Data
	enum { IDD = IDD_SAMRTPOESAMPLE_DIALOG };

	protected:
	virtual void DoDataExchange(CDataExchange* pDX);	// DDX/DDV support


// Implementation
protected:
	HICON m_hIcon;
	UINT_PTR m_nTimer;

    short m_Number;

    BOOL CheckUserInput();
    //BOOL CheckPowerEnableStatus();

	// Generated message map functions
	virtual BOOL OnInitDialog();
	afx_msg void OnPaint();
	afx_msg HCURSOR OnQueryDragIcon();
	DECLARE_MESSAGE_MAP()
	UINT hex2uint(CString h);

public:
    afx_msg void OnCbnSelchangeComboCardNumber();
    afx_msg void OnDestroy();
	afx_msg void OnBnClickedButtonSet4();
	afx_msg void OnBnClickedButtonSet3();
	afx_msg void OnBnClickedButtonSet7();
	afx_msg void OnBnClickedButtonRead3();
	afx_msg void OnBnClickedButtonRead2();
	afx_msg void OnBnClickedButtonSet15();
	afx_msg void OnBnClickedButtonSet16();
	afx_msg void OnBnClickedButtonSet17();
	afx_msg void OnBnClickedButtonSet22();
	afx_msg void OnBnClickedButtonSet23();
	afx_msg void OnBnClickedButtonSet25();
	afx_msg void OnBnClickedButtonSet27();
	afx_msg void OnBnClickedButtonSet28();
	afx_msg void OnBnClickedButtonSet29();
	afx_msg void OnBnClickedButtonSet30();
	afx_msg void OnBnClickedButtonSet31();
	afx_msg void OnBnClickedButtonSet32();
	afx_msg void OnBnClickedButtonSet26();
	afx_msg void OnBnClickedButtonSet24();
	afx_msg void OnBnClickedButtonSet33();
};
