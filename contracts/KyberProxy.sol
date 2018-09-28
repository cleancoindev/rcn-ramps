pragma solidity ^0.4.24;

import "./vendors/kyber/KyberNetworkProxy.sol";
import "./vendors/kyber/KyberNetwork.sol";
import "./vendors/kyber/ERC20Interface.sol";
import "./interfaces/TokenConverter.sol";
import "./utils/Ownable.sol";

contract KyberProxy is TokenConverter, Ownable {
    
    uint256 constant internal MAX_UINT = uint256(0) - 1;
    ERC20 constant internal ETH_TOKEN_ADDRESS = ERC20(0x00eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee);

    KyberNetworkProxy kyber;

    event ETHReceived(address indexed sender, uint amount);
    event Swap(address indexed sender, ERC20 srcToken, ERC20 destToken, uint amount);

    constructor (KyberNetworkProxy _kyber) public {
        kyber = _kyber;
    }

    function getReturn(
        Token from,
        Token to, 
        uint256 srcQty
    ) external view returns (uint256) {
        ERC20 srcToken = ERC20(from);
        ERC20 destToken = ERC20(to);   
        (uint256 amount,) = kyber.getExpectedRate(srcToken, destToken, srcQty);
        return amount;
    }

    function convert(
        Token from,
        Token to, 
        uint256 srcQty, 
        uint256 minReturn
    ) external payable returns (uint256 destAmount) {

        ERC20 srcToken = ERC20(from);
        ERC20 destToken = ERC20(to);       

        if (srcToken == ETH_TOKEN_ADDRESS && destToken != ETH_TOKEN_ADDRESS) {
            require(msg.value == srcQty, "ETH not enought");
            execSwapEtherToToken(srcToken, srcQty, msg.sender);
        } else if (srcToken != ETH_TOKEN_ADDRESS && destToken == ETH_TOKEN_ADDRESS) {
            require(msg.value == 0, "ETH not required");    
            execSwapTokenToEther(srcToken, srcQty, destToken);
        } else {
            require(msg.value == 0, "ETH not required");    
            execSwapTokenToToken(srcToken, srcQty, destToken, msg.sender);
        }

        require(destAmount > minReturn, "Return amount too low");   
        emit Swap(msg.sender, srcToken, destToken, destAmount);
    
        return destAmount;
    }

    /*
    @dev Swap the user's ETH to ERC20 token
    @param token destination token contract address
    @param destAddress address to send swapped tokens to
    */
    function execSwapEtherToToken(
        ERC20 token, 
        uint srcQty,
        address destAddress) 
    internal returns (uint) {

        (uint minConversionRate,) = kyber.getExpectedRate(ETH_TOKEN_ADDRESS, token, srcQty);

        // Swap the ETH to ERC20 token
        uint destAmount = kyber.swapEtherToToken.value(srcQty)(token, minConversionRate);

        // Send the swapped tokens to the destination address
        require(token.transfer(destAddress, destAmount));

        return destAmount;

    }

    /*
    @dev Swap the user's ERC20 token to ETH
    @param token source token contract address
    @param tokenQty amount of source tokens
    @param destAddress address to send swapped ETH to
    */
    function execSwapTokenToEther(
        ERC20 token, 
        uint256 tokenQty, 
        address destAddress
    ) internal returns (uint) {
            
        // Check that the player has transferred the token to this contract
        require(token.transferFrom(msg.sender, this, tokenQty), "Error pulling tokens");

        // Set the spender's token allowance to tokenQty
        require(token.approve(kyber, tokenQty));

        (uint minConversionRate,) = kyber.getExpectedRate(token, ETH_TOKEN_ADDRESS, tokenQty);

        // Swap the ERC20 token to ETH
        uint destAmount = kyber.swapTokenToEther(token, tokenQty, minConversionRate);

        // Send the swapped ETH to the destination address
        destAddress.transfer(destAmount);

        return destAmount;

    }

    /*
    @dev Swap the user's ERC20 token to another ERC20 token
    @param srcToken source token contract address
    @param srcQty amount of source tokens
    @param destToken destination token contract address
    @param destAddress address to send swapped tokens to
    */
    function execSwapTokenToToken(
        ERC20 srcToken, 
        uint256 srcQty, 
        ERC20 destToken, 
        address destAddress
    ) internal returns (uint) {

        // Check that the player has transferred the token to this contract
        require(srcToken.transferFrom(msg.sender, this, srcQty), "Error pulling tokens");

        // Set the spender's token allowance to tokenQty
        require(srcToken.approve(kyber, srcQty));

        (uint minConversionRate,) = kyber.getExpectedRate(srcToken, ETH_TOKEN_ADDRESS, srcQty);

        // Swap the ERC20 token to ERC20
        uint destAmount = kyber.swapTokenToToken(srcToken, srcQty, destToken, minConversionRate);

        // Send the swapped tokens to the destination address
        require(destToken.transfer(destAddress, destAmount));

        return destAmount;
    }

    function withdrawTokens(
        Token _token,
        address _to,
        uint256 _amount
    ) external onlyOwner returns (bool) {
        return _token.transfer(_to, _amount);
    }

    function withdrawEther(
        address _to,
        uint256 _amount
    ) external onlyOwner {
        _to.transfer(_amount);
    }

    function setConverter(
        KyberNetworkProxy _converter
    ) public onlyOwner returns (bool) {
        kyber = _converter;
    }

    function getConverter() public view returns (address) {
        return address(kyber);
    }

    function() external payable {
        emit ETHReceived(msg.sender, msg.value);
    }
	
}