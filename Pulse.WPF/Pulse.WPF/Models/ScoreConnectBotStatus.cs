using System;
using Pulse.WPF.Helpers;

namespace Pulse.WPF.Models
{
    /// <summary>
    /// Cloud (Sportzcast "BOT") connection state, as reported by the
    /// <c>api/v2/configuration/get-bot-configuration-status</c> endpoint.
    /// Tracks whether the ScoreConnect III instance can currently reach the
    /// configured BOT server (default <c>scorebot.sportzcast.net</c>) and
    /// what its assigned ScoreConnect ID is.
    /// </summary>
    public class ScoreConnectBotStatus : ObservableObject
    {
        private bool _isConnected;
        public bool IsConnected { get => _isConnected; set => Set(ref _isConnected, value); }

        private DateTime? _lastConnectedAt;
        public DateTime? LastConnectedAt
        {
            get => _lastConnectedAt;
            set => Set(ref _lastConnectedAt, value);
        }

        private string _scoreConnectId = "";
        public string ScoreConnectId { get => _scoreConnectId; set => Set(ref _scoreConnectId, value); }

        private string _botServerAddress = "";
        public string BotServerAddress
        {
            get => _botServerAddress;
            set => Set(ref _botServerAddress, value);
        }

        private string _lastErrorMessage = "";
        public string LastErrorMessage
        {
            get => _lastErrorMessage;
            set => Set(ref _lastErrorMessage, value);
        }
    }
}
