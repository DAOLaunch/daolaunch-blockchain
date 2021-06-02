// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.6.12;

import "./Presale01.sol";
import "../common/SafeMath.sol";
import "../common/Ownable.sol";
import "./IERC20.sol";
import "../common/TransferHelper.sol";
import "../common/PresaleHelper.sol";

interface IPresaleFactory {
    function registerPresale(address _presaleAddress) external;

    function presaleIsRegistered(address _presaleAddress)
        external
        view
        returns (bool);
}

interface IUniswapV2Locker {
    function lockLPToken(
        address _lpToken,
        uint256 _amount,
        uint256 _unlock_date,
        address payable _referral,
        bool _fee_in_eth,
        address payable _withdrawer
    ) external payable;
}

contract PresaleGenerator01 is Ownable {
    using SafeMath for uint256;

    IPresaleFactory public PRESALE_FACTORY;
    IPresaleSettings public PRESALE_SETTINGS;

    struct PresaleParams {
        uint256 amount;
        uint256 tokenPrice;
        uint256 maxSpendPerBuyer;
        uint256 minSpendPerBuyer;
        uint256 hardcap;
        uint256 softcap;
        uint256 liquidityPercent;
        uint256 listingRate; // sale token listing price on uniswap
        uint256 startblock;
        uint256 endblock;
        uint256 lockPeriod;
        uint256 uniswapListingTime;
    }

    constructor() public {
        PRESALE_FACTORY = IPresaleFactory(
            0xD2fc87C398D2e93d852830a1688D6E5E42281489
        );
        PRESALE_SETTINGS = IPresaleSettings(
            0xF8DA618A73dd5bb2dd4bBf69961192F7A32533ef
        );
    }

    /**
     * @notice Creates a new Presale contract and registers it in the PresaleFactory.sol.
     */
    function createPresale(
        address payable _presaleOwner,
        IERC20 _presaleToken,
        IERC20 _baseToken,
        address[] memory white_list,
        uint256[12] memory uint_params,
        address payable _caller
    ) public payable {
        PresaleParams memory params;
        params.amount = uint_params[0];
        params.tokenPrice = uint_params[1];
        params.maxSpendPerBuyer = uint_params[2];
        params.minSpendPerBuyer = uint_params[3];
        params.hardcap = uint_params[4];
        params.softcap = uint_params[5];
        params.liquidityPercent = uint_params[6];
        params.listingRate = uint_params[7];
        params.startblock = uint_params[8];
        params.endblock = uint_params[9];
        params.lockPeriod = uint_params[10];
        params.uniswapListingTime = uint_params[11];

        if (params.lockPeriod < 4 weeks) {
            params.lockPeriod = 4 weeks;
        }

        require(params.uniswapListingTime > params.endblock);
        // Charge ETH fee for contract creation
        require(
            msg.value == PRESALE_SETTINGS.getEthCreationFee(),
            "FEE NOT MET"
        );

        require(params.amount >= 10000, "MIN DIVIS"); // minimum divisibility
        require(params.endblock > params.startblock, "INVALID BLOCK TIME");
        require(params.tokenPrice.mul(params.hardcap) > 0, "INVALID PARAMS"); // ensure no overflow for future calculations
        require(
            params.liquidityPercent >= 300 && params.liquidityPercent <= 1000,
            "MIN LIQUIDITY"
        ); // 30% minimum liquidity lock
        uint256 tokensRequiredForPresale = PresaleHelper
            .calculateAmountRequired(
            params.amount,
            params.tokenPrice,
            params.listingRate,
            params.liquidityPercent,
            PRESALE_SETTINGS.getBaseFee()
        );

        Presale01 newPresale = (new Presale01){value: msg.value}(address(this));

        TransferHelper.safeTransferFrom(
            address(_presaleToken),
            address(msg.sender),
            address(newPresale),
            tokensRequiredForPresale
        );
        newPresale.init1(
            _presaleOwner,
            params.amount,
            params.tokenPrice,
            params.maxSpendPerBuyer,
            params.minSpendPerBuyer,
            params.hardcap,
            params.softcap,
            params.liquidityPercent,
            params.listingRate,
            params.startblock,
            params.endblock,
            params.lockPeriod
        );
        newPresale.init2(
            _baseToken,
            _presaleToken,
            PRESALE_SETTINGS.getBaseFee(),
            PRESALE_SETTINGS.getTokenFee(),
            params.uniswapListingTime,
            PRESALE_SETTINGS.getEthAddress(),
            PRESALE_SETTINGS.getTokenAddress()
        );
        newPresale.init3(white_list, _caller);
        PRESALE_FACTORY.registerPresale(address(newPresale));
    }
}
