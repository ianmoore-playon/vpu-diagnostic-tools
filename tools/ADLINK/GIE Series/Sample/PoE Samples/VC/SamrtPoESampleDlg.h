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
    short m_Number;

    BOOL CheckUserInput();

	// Generated message map functions
	virtual BOOL OnInitDialog();
	afx_msg void OnPaint();
	afx_msg HCURSOR OnQueryDragIcon();
	DECLARE_MESSAGE_MAP()
public:
    afx_msg void OnCbnSelchangeComboCardNumber();
    afx_msg void OnBnClickedButtonSet();
    afx_msg void OnDestroy();
};
