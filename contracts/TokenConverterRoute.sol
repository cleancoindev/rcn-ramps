pragma solidity ^0.4.24;

import "./interfaces/TokenConverter.sol";
import "./interfaces/AvailableProvider.sol";
import "./interfaces/Token.sol";
import "./utils/Ownable.sol";
import "./vendors/bancor/converter/BancorGasPriceLimit.sol";


contract TokenConverterRoute is TokenConverter, Ownable {
    
    uint256 constant internal MAX_UINT = uint256(0) - 1;
    TokenConverter[] private converters;
    mapping (address => address) private availability;
    
    function addConverter(TokenConverter converter, AvailableProvider availabilityContract) onlyOwner public {
        converters.push(converter);
        availability[converter] = availabilityContract;        
    }
    
    function converter(Token _from, Token _to, uint256 _amount, uint256 _minReturn) external payable returns (uint256 amount) {
        address betterProxy = _getBetterProxy(_from, _to, _amount);
        TokenConverter converter =  TokenConverter(betterProxy);
        return converter.convert.value(msg.value)(_from, _to, _amount, _minReturn);   
    }

    function getReturn(Token _from, Token _to, uint256 _amount) external view returns (uint256 amount) {
        address betterProxy = _getBetterProxy(_from, _to, _amount);
        TokenConverter converter =  TokenConverter(betterProxy);
        return converter.getReturn(_from, _to, _amount);
    }
    
    function _getBetterProxy(Token _from, Token _to, uint256 _amount) private view returns (address) {
        uint minRate = MAX_UINT;
        address betterProxy = 0x0;
     
        for (uint256 i = 0; i < converters.length; i++) {
            
            TokenConverter converter = TokenConverter(converters[i]);
            if (_isAvailable(converter, gasleft())) {
                
                uint newRate = converter.getReturn(_from, _to, _amount);
                if  (newRate > 0 && newRate < minRate) {
                    minRate = newRate;
                    betterProxy = converter;
                }
                
            }
                
        }
        
        return betterProxy;
    }

    function _isAvailable(address converter, uint256 _gasPrice) private view returns (bool) {
        
        if (availability[converter] == 0x0)
            return AvailableProvider(converter).isAvailable(_gasPrice);            
            
        //bancor workaround
        return (_gasPrice < BancorGasPriceLimit(availability[converter]).gasPrice());
    }

}