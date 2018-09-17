pragma solidity ^0.4.19;


import "./interfaces/Token.sol";
import "./interfaces/TokenConverter.sol";
import "./test/bancor/converter/BancorConverter.sol";
import "./test/bancor/token/interfaces/IERC20Token.sol";
import "./utils/Ownable.sol";

contract BancorProxy is TokenConverter, Ownable {
    IBancorConverter converterEthBnt;

    mapping(address => mapping(address => BancorConverter)) public converterOf;
    mapping(address => mapping(address => address)) public routerOf;
    mapping(address => mapping(address => IERC20Token[])) public pathCache;

    Token ethToken;

    constructor(
        Token _ethToken
    ) public {
        ethToken = _ethToken;
    }

    function setConverter(
        Token _token1,
        Token _token2,
        BancorConverter _converter
    ) public onlyOwner returns (bool) {
        converterOf[_token1][_token2] = _converter;
        converterOf[_token2][_token1] = _converter;
        uint256 approve = uint256(0) - 1;
        require(_token1.approve(_converter, approve), "Error approving transfer token 1");
        require(_token2.approve(_converter, approve), "Error approving transfer token 2");
        clearCache(_token1, _token2);
        return true;
    }

    function setRouter(
        address _token1,
        address _token2,
        address _router
    ) external onlyOwner returns (bool) {
        routerOf[_token1][_token2] = _router;
        routerOf[_token2][_token1] = _router;
        return true;
    }

    function clearCache(
        Token from,
        Token to
    ) public onlyOwner returns (bool) {
        pathCache[from][to].length = 0;
        pathCache[to][from].length = 0;
        return true;
    }

    function getPath(
        BancorConverter converter,
        Token from,
        Token to
    ) private returns (IERC20Token[]) {
        if (pathCache[from][to].length != 0) {
            return pathCache[from][to];
        } else {
            IERC20Token token = converter.token();
            pathCache[from][to] = [IERC20Token(from), token, IERC20Token(to)];
            return pathCache[from][to];
        }
    }

    function getReturn(Token from, Token to, uint256 sell) external view returns (uint256 amount){
        return _getReturn(from, to, sell);
    }

    function _getReturn(Token _from, Token _to, uint256 sell) internal view returns (uint256 amount){
        Token from = _from == ETH_ADDRESS ? Token(ethToken) : _from;
        Token to = _to == ETH_ADDRESS ? Token(ethToken) : _to;
        BancorConverter converter = converterOf[from][to];
        if (converter != address(0)) {
            return converter.getReturn(IERC20Token(from), IERC20Token(to), sell);
        }

        Token router = Token(routerOf[from][to]);
        if (router != address(0)) {
            converter = converterOf[router][to];
            return converter.getReturn(
                IERC20Token(router),
                IERC20Token(to),
                _getReturn(from, router, sell)
            );
        }
        revert("No routing found - BancorProxy");
    }

    function convert(Token _from, Token _to, uint256 sell, uint256 minReturn) external payable returns (uint256 amount){
        Token from = _from == ETH_ADDRESS ? Token(ethToken) : _from;
        Token to = _to == ETH_ADDRESS ? Token(ethToken) : _to;

        if (from == ethToken) {
            require(msg.value == sell, "ETH not enought");
        } else {
            require(msg.value == 0, "ETH not required");
            require(from.transferFrom(msg.sender, this, sell), "Error pulling tokens");
        }

        amount = _convert(from, to, sell);
        require(amount > minReturn, "Return amount too low");

        if (to == ethToken) {
            msg.sender.transfer(amount);
        } else {
            require(to.transfer(msg.sender, amount), "Error sending tokens");
        }
    }

    function _convert(
        Token from,
        Token to,   
        uint256 sell
    ) internal returns (uint256) {
        BancorConverter converter = converterOf[from][to];
        
        uint256 amount;
        if (converter != address(0)) {
            amount = converter.quickConvert
                .value(from == ethToken ? sell : 0)(
                getPath(converter, from, to),
                sell,
                1
            );
        } else {
            Token router = Token(routerOf[from][to]);
            if (router != address(0)) {
                uint256 routerAmount = _convert(from, router, sell);
                converter = converterOf[router][to];
                amount = converter.quickConvert
                    .value(router == ethToken ? routerAmount : 0)(
                    getPath(converter, router, to),
                    routerAmount,
                    1
                );
            }
        }

        return amount;
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

    function() external payable {}
}
