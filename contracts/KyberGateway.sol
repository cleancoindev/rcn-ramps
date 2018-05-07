pragma solidity ^0.4.19;

import "./interfaces/Engine.sol";
import "./interfaces/Cosigner.sol";
import "./utils/RpSafeMath.sol";
import "./KyberMock.sol";


contract KyberGateway is RpSafeMath {
    address constant internal ETH_TOKEN_ADDRESS = 0x00eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee;

    Token public RCN;
    Token public ETH = Token(ETH_TOKEN_ADDRESS);

    constructor(Token _RCN) public {
        RCN = _RCN;
    }

    function lend(
        KyberMock kyber,
        Engine engine,
        uint idLoan,
        Cosigner cosigner,
        bytes cosignerData,
        bytes oracleData
    ) public payable returns (bool) {
        uint256 targetAmount = kyber.convertRate(engine.getAmount(idLoan), kyber.rateRE());

        require(msg.value >= targetAmount);

        uint256 returnAmount = safeSubtract(msg.value, targetAmount);
        uint256 totalTokens = kyber.trade.value(targetAmount)(ETH, targetAmount, RCN, this, 10 ** 30, 0, this);

        RCN.approve(address(engine), totalTokens);

        engine.lend(idLoan, oracleData, cosigner, cosignerData);

        msg.sender.transfer(returnAmount);// if the sender is a contract, the contract needs a fallback function payable
    }
}
